# OGC API Features -----------------------------------------------------------
#
# The BDL side has no record cap to work around (the WFS advertises
# CountDefault = 1 000 000), but it does page, and the subarea collections
# are large enough that paging matters: one regional directorate holds well
# over a hundred thousand polygons. This walks the `next` links and stops when
# the server stops offering one.

OAPIF_PAGE <- 5000L

oapif_url <- function(base, collection, endpoint = "items") {
  paste0(base, "/collections/", collection, "/", endpoint)
}

#' @keywords internal
#' @noRd
oapif_collections <- function(base) {
  # Stable for months at a time; no point re-fetching within a session.
  out <- gp_json(paste0(base, "/collections"), list(f = "json"),
                 ttl = 7 * 24 * 3600)
  out$collections$id
}

# Attributes only, no geometry. Used for routing and lookups, where dragging
# the polygons across the wire would cost seconds for nothing.
#' @keywords internal
#' @noRd
oapif_properties <- function(base, collection, bbox = NULL, limit = 1000L) {
  params <- list(limit = limit, skipGeometry = "true", f = "json")
  if (!is.null(bbox)) params$bbox <- paste(bbox, collapse = ",")
  out <- gp_json(oapif_url(base, collection), params)
  props <- out$features$properties
  if (is.null(props) || nrow(props) == 0L) return(NULL)
  props
}

# Attributes plus the feature id, so a single unit can be fetched later
# without pulling the whole collection's geometry across the wire.
#' @keywords internal
#' @noRd
oapif_catalogue <- function(base, collection, limit = 10000L) {
  out <- gp_json(oapif_url(base, collection),
                 list(limit = limit, skipGeometry = "true", f = "json"),
                 ttl = 7 * 24 * 3600)
  props <- out$features$properties
  if (is.null(props) || nrow(props) == 0L) return(NULL)
  props$.id <- out$features$id
  props
}

# One feature, by id, with its geometry.
#' @keywords internal
#' @noRd
oapif_item <- function(base, collection, id) {
  txt <- gp_text(paste0(oapif_url(base, collection), "/", id), list(f = "json"),
                 ttl = 7 * 24 * 3600)
  suppressWarnings(sf::st_read(txt, quiet = TRUE))
}

#' @keywords internal
#' @noRd
oapif_items <- function(base, collection, bbox = NULL, page = OAPIF_PAGE,
                        max_features = 2e5, quiet = FALSE) {
  url <- oapif_url(base, collection)
  bbox_str <- if (is.null(bbox)) NULL else paste(bbox, collapse = ",")
  params <- drop_null(list(limit = page, bbox = bbox_str, f = "json"))

  # Build the counting probe from scratch. Appending `limit = 1` to `params`
  # would put two `limit` values in the query string; the server honours the
  # first, so the probe would quietly download a full page of geometry --
  # measured at 370 MB on the national forest-inspectorate collection.
  probe <- drop_null(list(limit = 1L, bbox = bbox_str, skipGeometry = "true",
                          f = "json"))
  first <- gp_json(url, probe)
  n <- as.integer(first$numberMatched %||% NA)

  if (!is.na(n) && n == 0L) return(NULL)
  if (!is.na(n) && n > max_features) {
    rlang::abort(
      c(paste0("This request would return ", n, " features."),
        i = paste0("The limit is ", max_features,
                   "; narrow the area, or raise `max_features` deliberately.")),
      class = "rgeopl_too_large"
    )
  }
  if (!quiet && !is.na(n)) {
    message("  ", collection, ": ", n, " features")
  }

  # Paging is driven by explicit offsets rather than by following the server's
  # `next` links. Measured on this service: at offset 0 it reports the true
  # total and offers a next link, but from the second page on it reports only
  # what remains *and stops offering a next link altogether* -- so a client
  # that trusts those links stops at 10 000 features and never learns that
  # thousands are missing. The totals from the first request are authoritative;
  # keep asking until they are accounted for.
  pages <- ceiling(n / page)
  bar <- pb_new(
    pages, quiet = quiet,
    format = paste("  {cli::pb_current}/{cli::pb_total} pages",
                   "{cli::pb_bar} {cli::pb_percent} {cli::pb_eta_str}")
  )
  on.exit(pb_done(bar), add = TRUE)

  parts <- vector("list", pages)
  for (i in seq_len(pages)) {
    pb_tick(bar)
    got <- gp_text(url, c(params, list(offset = (i - 1L) * page)))
    parts[[i]] <- suppressWarnings(sf::st_read(got, quiet = TRUE))
    if (nrow(parts[[i]]) == 0L) break
  }

  out <- do.call(rbind, parts[!vapply(parts, is.null, logical(1))])
  if (!is.na(n) && nrow(out) < n) {
    rlang::warn(c(
      paste0("Expected ", n, " features but assembled ", nrow(out), "."),
      i = "The result is incomplete; re-run before relying on it."
    ))
  }
  out
}
