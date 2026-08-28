# ArcGIS REST index queries -------------------------------------------------
#
# The GUGiK indexes sit behind an ArcGIS MapServer whose layers all report
# maxRecordCount = 1000. A plain spatial query therefore returns at most 1000
# tiles and sets exceededTransferLimit, which is how a request for a whole
# voivodeship quietly turns into a request for part of one.
#
# `returnIdsOnly=true` is not subject to that cap: it answers with the complete
# object ID list in a single response (measured: 1 637 675 IDs for the whole
# country). So the strategy is
#
#   1. ask how many there are            (returnCountOnly)
#   2. small enough? one request, done
#   3. otherwise ask for every ID        (returnIdsOnly)
#   4. fetch attributes in chunks by ID  (POST, because the ID lists are long)
#
# and the row count is then checked against step 1. A short result raises,
# rather than being handed back as if it were complete.

ARCGIS_PAGE <- 1000L

arcgis_query_url <- function(service, layer) {
  paste0(service, "/", layer, "/query")
}

# The envelope syntax ArcGIS expects, in the CRS we work in.
arcgis_envelope <- function(bbox, epsg = CRS_PL1992) {
  sprintf(
    "{'xmin':%.4f,'ymin':%.4f,'xmax':%.4f,'ymax':%.4f,'spatialReference':{'wkid':%d}}",
    bbox[["xmin"]], bbox[["ymin"]], bbox[["xmax"]], bbox[["ymax"]], as.integer(epsg)
  )
}

arcgis_spatial_params <- function(aoi, epsg = CRS_PL1992) {
  list(
    geometry = arcgis_envelope(aoi_bbox(aoi, crs = epsg), epsg),
    geometryType = "esriGeometryEnvelope",
    spatialRel = "esriSpatialRelIntersects",
    inSR = as.character(as.integer(epsg))
  )
}

# Field names a layer actually publishes. The point-cloud index carries a
# slightly different schema from the elevation index, so asking for a fixed
# list would fail on one of them.
arcgis_fields <- function(service, layer) {
  meta <- gp_json(paste0(service, "/", layer), list(f = "json"),
                  ttl = 30 * 24 * 3600)
  meta$fields$name
}

arcgis_count <- function(url, spatial) {
  out <- gp_json(url, c(spatial, list(returnCountOnly = "true", f = "json")))
  as.integer(out$count)
}

arcgis_ids <- function(url, spatial) {
  out <- gp_json(url, c(spatial, list(returnIdsOnly = "true", f = "json")))
  list(field = out$objectIdFieldName, ids = out$objectIds)
}

# One page of features, as sf.
#
# Esri JSON, not GeoJSON, and the difference is not cosmetic: this server's
# GeoJSON writer silently omits fields of type esriFieldTypeSingle. On the
# orthophoto index that is `piksel`, the pixel size, which vanished from the
# result with no error anywhere. Esri JSON returns it, GDAL reads that format
# directly, and `outSR` is honoured either way.
arcgis_page <- function(url, params, epsg, method = "GET") {
  txt <- gp_text(url, c(params, list(f = "json", outSR = as.character(as.integer(epsg)))),
                 method = method)
  suppressWarnings(sf::st_read(txt, quiet = TRUE))
}

# One request per feature, sent concurrently. For scattered areas this is the
# whole difference between asking about a plot and asking about the country.
# Cached answers are used without a request, so re-running a script over the
# same plots costs nothing.
#' @keywords internal
#' @noRd
arcgis_query_each <- function(service, layer, aoi, fields, epsg = CRS_PL1992,
                              n_active = NULL, quiet = FALSE) {
  url <- arcgis_query_url(service, layer)
  field_str <- paste(fields, collapse = ",")

  params <- lapply(seq_along(aoi$geom), function(i) {
    c(arcgis_spatial_params(new_aoi(aoi$geom[i]), epsg),
      list(outFields = field_str, returnGeometry = "true", f = "json",
           outSR = as.character(as.integer(epsg))))
  })
  keys <- vapply(params, function(p) cache_key("text", url, p, "GET"),
                 character(1))
  bodies <- lapply(keys, meta_get)

  todo <- which(vapply(bodies, is.null, logical(1)))
  if (length(todo)) {
    resps <- perform_many(lapply(params[todo], function(p) gp_req(url, p)),
                          n = n_active, quiet = quiet, what = "index queries")
    ok <- split_responses(resps, quiet, "index queries")
    for (j in seq_along(todo)) {
      if (!ok[j]) next
      txt <- httr2::resp_body_string(resps[[j]])
      meta_set(keys[todo[j]], txt)
      bodies[[todo[j]]] <- txt
    }
  }

  # A single feature can still outgrow one page. Those few go back through the
  # paged path rather than being returned a thousand rows short.
  truncated <- which(vapply(bodies, function(b) {
    !is.null(b) && grepl('"exceededTransferLimit":true', b, fixed = TRUE)
  }, logical(1)))
  parts <- lapply(seq_along(bodies), function(i) {
    if (i %in% truncated) {
      return(arcgis_query(service, layer, new_aoi(aoi$geom[i]), fields, epsg,
                          quiet = TRUE))
    }
    if (is.null(bodies[[i]])) return(NULL)
    out <- tryCatch(suppressWarnings(sf::st_read(bodies[[i]], quiet = TRUE)),
                    error = function(e) NULL)
    if (is.null(out) || nrow(out) == 0L) NULL else out
  })
  if (length(truncated)) {
    say(quiet, "  ", length(truncated),
        " feature(s) needed paging on their own")
  }

  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0L) return(empty_features(fields, epsg))

  out <- do.call(rbind, parts)
  # Neighbouring plots land on the same map sheets. One row per file.
  if ("url_do_pobrania" %in% names(out)) {
    out <- out[!duplicated(out$url_do_pobrania), , drop = FALSE]
  }
  out
}

#' @keywords internal
#' @noRd
arcgis_query <- function(service, layer, aoi, fields, epsg = CRS_PL1992,
                         max_records = 2e5, quiet = FALSE) {
  url <- arcgis_query_url(service, layer)
  spatial <- arcgis_spatial_params(aoi, epsg)
  field_str <- paste(fields, collapse = ",")

  n <- arcgis_count(url, spatial)
  if (n == 0L) return(empty_features(fields, epsg))
  if (n > max_records) {
    rlang::abort(
      c(paste0("One bounding box over this area holds ", n, " index records."),
        i = paste0("The limit is ", max_records, "."),
        i = paste0("If the area is many small plots far apart, ask for them ",
                   "one at a time with by_feature = TRUE."),
        i = "Otherwise narrow the area, or raise `max_records` deliberately."),
      class = "rgeopl_too_large"
    )
  }

  if (n <= ARCGIS_PAGE) {
    out <- arcgis_page(
      url,
      c(spatial, list(outFields = field_str, returnGeometry = "true")),
      epsg
    )
    return(check_complete(out, n))
  }

  ids <- arcgis_ids(url, spatial)$ids
  if (length(ids) < n) {
    rlang::warn(paste0(
      "The server reported ", n, " records but listed only ", length(ids),
      " ids; continuing with the ids it gave."
    ))
  }
  batches <- chunk(ids, ARCGIS_PAGE)

  say(quiet, "  ", n, " records in ", length(batches), " requests")

  bar <- pb_new(
    length(batches), quiet = quiet,
    format = paste("  {cli::pb_current}/{cli::pb_total} requests",
                   "{cli::pb_bar} {cli::pb_percent} {cli::pb_eta_str}")
  )
  on.exit(pb_done(bar), add = TRUE)

  parts <- vector("list", length(batches))
  for (i in seq_along(batches)) {
    pb_tick(bar)
    parts[[i]] <- arcgis_page(
      url,
      list(objectIds = paste(batches[[i]], collapse = ","),
           outFields = field_str, returnGeometry = "true"),
      epsg,
      method = "POST"
    )
  }

  out <- do.call(rbind, parts)
  check_complete(out, length(ids))
}

# The whole point of the id-based fetch is that the count is known in advance.
# If the assembled table is short, say so instead of returning it silently.
check_complete <- function(x, expected) {
  if (nrow(x) < expected) {
    rlang::warn(c(
      paste0("Expected ", expected, " index records but assembled ", nrow(x), "."),
      i = "The result is incomplete. Re-run; if it persists, report it."
    ))
  }
  x
}

empty_features <- function(fields, epsg) {
  out <- as.data.frame(
    stats::setNames(rep(list(character(0)), length(fields)), fields),
    stringsAsFactors = FALSE
  )
  out$geometry <- sf::st_sfc(crs = sf::st_crs(epsg))
  sf::st_as_sf(out)
}
