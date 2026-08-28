# Many areas at once ----------------------------------------------------------
#
# The workload this exists for: hundreds or thousands of small plots scattered
# across the country. Asked as one bounding box, that is a question about
# Poland. Measured on 40 plots of 500 m radius: their own area is 31 km2, the
# box around them is 291 081 km2, and the elevation index answers with 1 410 846
# records instead of 1 507 -- a factor of 936 thrown away afterwards.
#
# So scattered areas are queried one feature at a time, and those queries go out
# concurrently. Measured on the same 40 plots: 13.9 s in sequence, 2.4 s with
# eight connections.
#
# Concurrency here is `httr2::req_perform_parallel()`, which runs many requests
# from one R process rather than many R processes. That distinction matters
# beyond speed: the download manifest is a read-modify-write of a single file,
# and it stays correct only because all the bookkeeping still happens on one
# thread. The same work under `furrr` with multisession workers would race on
# that file and lose records silently -- the files would be on disk and the
# cache would not know.

#' @keywords internal
#' @noRd
max_active <- function(n = NULL) {
  n <- n %||% getOption("rgeopl.max_active", 6L)
  max(1L, min(as.integer(n), 16L))
}

# Is this area scattered enough that one bounding box would be wasteful? The
# test is the box around everything against the sum of the boxes around each
# part; for a single feature they are equal and nothing changes.
#' @keywords internal
#' @noRd
aoi_scattered <- function(aoi, threshold = 4) {
  if (length(aoi$geom) < 2L) return(FALSE)
  box_area <- function(b) {
    max(b[["xmax"]] - b[["xmin"]], 1) * max(b[["ymax"]] - b[["ymin"]], 1)
  }
  whole <- box_area(aoi_bbox(aoi))
  parts <- sum(vapply(aoi_bbox(aoi, by_feature = TRUE), box_area, numeric(1)))
  whole > threshold * parts
}

# Perform requests concurrently, politely. These are public services run by
# public bodies; the cap is deliberate, and a failure on one request does not
# abandon the other nine hundred.
#' @keywords internal
#' @noRd
perform_many <- function(reqs, paths = NULL, n = NULL, quiet = FALSE,
                         what = "requests") {
  if (length(reqs) == 0L) return(list())
  if (length(reqs) == 1L) {
    resp <- tryCatch(
      if (is.null(paths)) httr2::req_perform(reqs[[1]])
      else httr2::req_perform(reqs[[1]], path = paths[[1]]),
      error = function(e) e
    )
    return(list(resp))
  }
  say(quiet, "  ", length(reqs), " ", what, ", ", max_active(n), " at a time")
  httr2::req_perform_parallel(
    reqs, paths = paths, max_active = max_active(n),
    progress = progress_on(quiet), on_error = "continue"
  )
}

# What came back, and what did not. `req_perform_parallel(on_error =
# "continue")` returns conditions in place of responses, so the failures are
# counted and reported rather than thrown away or allowed to look like data.
#' @keywords internal
#' @noRd
split_responses <- function(resps, quiet = FALSE, what = "requests") {
  ok <- vapply(resps, function(r) inherits(r, "httr2_response"), logical(1))
  if (any(!ok)) {
    first <- conditionMessage(resps[[which(!ok)[1]]])
    rlang::warn(c(
      paste0(sum(!ok), " of ", length(resps), " ", what, " failed."),
      i = paste0("First failure: ", substr(first, 1, 160)),
      i = "The rest of the result is complete; re-run to fill the gaps."
    ))
  }
  ok
}
