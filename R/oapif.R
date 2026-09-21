# OGC API Features -----------------------------------------------------------
#
# The BDL side has no record cap to work around (the WFS advertises
# CountDefault = 1 000 000), but it does page, and the collections are large
# enough that paging matters: one regional directorate holds well over a
# hundred thousand subarea polygons.
#
# Two things about that paging had to be measured rather than assumed, and each
# is written up where it is implemented: the server stops offering `next` links
# after the first page, so they cannot be walked (oapif_items), and a page
# counted in features is the wrong unit, because feature sizes here span three
# orders of magnitude (oapif_page_size).

# A page holds at most this many features, however small they are.
OAPIF_PAGE <- 5000L

# ...and at most this many bytes, however few features that turns out to be.
OAPIF_PAGE_BYTES <- 32e6

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

# What the service says it holds, without downloading any of it. The probe is
# built from scratch rather than by adding `limit = 1` to an existing parameter
# list: two `limit` values in one query string and the server honours the
# first, which would download a full page of geometry to count it.
#' @keywords internal
#' @noRd
oapif_count <- function(base, collection, bbox = NULL) {
  params <- drop_null(list(limit = 1L, skipGeometry = "true", f = "json",
                           bbox = if (is.null(bbox)) NULL else {
                             paste(bbox, collapse = ",")
                           }))
  out <- gp_json(oapif_url(base, collection), params)
  as.integer(out$numberMatched %||% NA)
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
  # `limit` is a ceiling the caller picked, not a promise from the service.
  # Silently returning the first thousand of something larger is the failure
  # this package was written to avoid; it should not go unremarked here.
  check_complete(props, oapif_count(base, collection, bbox))
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
  check_complete(props, oapif_count(base, collection))
}

# One feature, by id, with its geometry.
#' @keywords internal
#' @noRd
oapif_item <- function(base, collection, id) {
  txt <- gp_text(paste0(oapif_url(base, collection), "/", id), list(f = "json"),
                 ttl = 7 * 24 * 3600)
  suppressWarnings(sf::st_read(txt, quiet = TRUE))
}

# How many features to ask for at once.
#
# Counted in bytes rather than in features, because in these collections the
# two run in opposite directions. Measured on BDL: a subarea is 5 kB of polygon
# and there are hundreds of thousands of them, while `rdlp` holds seventeen
# features of 5.2 MB each, a regional directorate's outline being every forest
# boundary inside it. Between them the spread is a factor of a thousand, so one
# page of 5000 features is 26 MB of subareas and 475 MB of forest ranges -- and
# the gateway answers the second with an intermittent 502 rather than the data.
# Pages of 66 MB and 159 MB were both served without complaint, so the budget
# is set well under what the service has been seen to manage.
#
# One feature is fetched to measure it, which is one feature more than the walk
# needs. Keeping it as page one instead would save that, and would make the
# loop below read as a special case; the feature is the cheapest thing the
# collection has, so it is paid for rather than saved. The envelope and the
# links are counted in with it, which biases the estimate towards a smaller
# page -- the safe direction.
oapif_page_size <- function(base, collection, bbox = NULL, n = NA_integer_,
                            geometry = TRUE, budget = OAPIF_PAGE_BYTES) {
  # Attributes are small and uniform -- 5000 of them measured at 1.4 MB -- and
  # a single feature cannot be split across pages however large it is. Neither
  # case is worth a request to measure.
  if (!geometry || (!is.na(n) && n <= 1L)) return(OAPIF_PAGE)

  txt <- tryCatch(
    gp_text(oapif_url(base, collection),
            drop_null(list(limit = 1L, bbox = bbox, f = "json"))),
    error = function(e) NULL
  )
  if (is.null(txt)) return(OAPIF_PAGE)
  bytes <- nchar(txt, type = "bytes")
  if (!is.finite(bytes) || bytes <= 0) return(OAPIF_PAGE)
  max(1L, min(OAPIF_PAGE, as.integer(budget %/% bytes)))
}

#' @keywords internal
#' @noRd
oapif_items <- function(base, collection, bbox = NULL, page = NULL,
                        max_features = 2e5, geometry = TRUE, quiet = FALSE) {
  url <- oapif_url(base, collection)
  bbox_str <- if (is.null(bbox)) NULL else paste(bbox, collapse = ",")

  n <- oapif_count(base, collection, bbox_str)

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

  if (is.null(page)) {
    page <- oapif_page_size(base, collection, bbox_str, n, geometry)
  }
  params <- drop_null(list(
    limit = page, bbox = bbox_str, f = "json",
    skipGeometry = if (geometry) NULL else "true"
  ))

  # skipGeometry leaves `"geometry": null` on every feature rather than
  # omitting the member, which sf reads as a column of empty geometries: an sf
  # object that cannot be plotted, transformed or intersected. The properties
  # are taken directly instead, and what comes back is an ordinary data frame
  # that says what it is.
  read_page <- function(offset) {
    query <- c(params, list(offset = offset))
    if (geometry) {
      suppressWarnings(sf::st_read(gp_text(url, query), quiet = TRUE))
    } else {
      gp_json(url, query)$features$properties
    }
  }

  # Paging is driven by explicit offsets rather than by following the server's
  # `next` links. Measured on this service: at offset 0 it reports the true
  # total and offers a next link, but from the second page on it reports only
  # what remains *and stops offering a next link altogether* -- so a client
  # that trusts those links stops at 10 000 features and never learns that
  # thousands are missing. The totals from the first request are authoritative;
  # keep asking until they are accounted for.
  # With a total to work from, the number of pages is known. Without one --
  # some services simply do not report it -- the only end marker left is a
  # page that comes back short, so keep asking until one does.
  pages <- if (is.na(n)) Inf else ceiling(n / page)
  bar <- pb_new(
    if (is.finite(pages)) pages else NA, quiet = quiet,
    format = paste("  {cli::pb_current}/{cli::pb_total} pages",
                   "{cli::pb_bar} {cli::pb_percent} {cli::pb_eta_str}")
  )
  on.exit(pb_done(bar), add = TRUE)

  parts <- list()
  i <- 0L
  while (i < pages) {
    i <- i + 1L
    pb_tick(bar)
    part <- read_page((i - 1L) * page)
    if (is.null(part) || nrow(part) == 0L) break
    parts[[i]] <- part
    if (!is.finite(pages)) {
      if (nrow(part) < page) break
      if (i * page >= max_features) {
        rlang::warn(c(
          paste0("Stopped at ", i * page, " features, the `max_features` ",
                 "limit, and the service did not say how many there are."),
          i = "Narrow the area, or raise `max_features` deliberately."))
        break
      }
    }
  }

  # Pages do not always agree on their columns: a property absent from every
  # feature on one page is absent from that page's data frame.
  out <- rbind_parts(parts)
  if (!is.null(out) && !is.na(n) && nrow(out) < n) {
    rlang::warn(c(
      paste0("Expected ", n, " features but assembled ", nrow(out), "."),
      i = "The result is incomplete; re-run before relying on it."
    ))
  }
  out
}
