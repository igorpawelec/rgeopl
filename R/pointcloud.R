# Point clouds ----------------------------------------------------------------
#
# This is where the package stops, and stopping here is deliberate. Turning
# LAS files into a catalogue means lidR, and lidR left CRAN on 2026-06-09,
# archived along with the rlas package it reads through. It is alive and
# installable -- r-universe carries lidR 4.3.2 and rlas 1.9.5 with binaries --
# but there is no way to name it in DESCRIPTION that leaves a check clean:
# Suggests and Enhances both make dependency resolution fetch it from CRAN and
# fail, and leaving it undeclared while calling requireNamespace() raises a
# WARNING. All three measured.
#
# So this delivers the files and the one thing the files do not carry, and the
# caller spends a line on lidR. Read straight out of the LAS headers, a 2024
# tile declares EPSG:2180 while 2012 and 2014 tiles carry a projection record
# three bytes long, which is to say empty -- and a catalogue with no
# coordinate system is the kind of thing that goes unnoticed until an overlay
# lands in the wrong place.

#' Point cloud tiles, downloaded and identified
#'
#' Fetches what an index points at, checks it is one survey, and returns the
#' files with the coordinate system the archive says they are in. The pair to
#' [tile_mosaic()]: that one ends the raster chain, this one ends the point
#' cloud chain, one step short of a `lidR` catalogue.
#'
#' @param index A point cloud index from [pointcloud_request()], filtered to
#'   what you want. It must describe one survey -- see below.
#' @param allow_mixed Accept more than one survey. Off by default: two flights
#'   over one place means returns from both in the same cloud, which inflates
#'   density, doubles the canopy surface and puts two ground levels under it.
#' @param overwrite,max_active,quiet Passed to [tile_download()].
#'
#' @return The index, keeping only rows whose file arrived, with `path` (the
#'   cached `.laz`) and `epsg` added.
#'
#' @section Reading them:
#' `lidR` is the tool for what comes next, and it needs one thing the files do
#' not provide. Older surveys leave the projection record empty, so the
#' coordinate system has to come from the index:
#'
#' ```
#' pc  <- pointcloud_get(subset(idx, year == 2024))
#' ctg <- lidR::readLAScatalog(pc$path)
#' sf::st_crs(ctg) <- pc$epsg[1]
#' ```
#'
#' `lidR` is not on CRAN -- it was archived on 2026-06-09 together with `rlas`
#' -- but it is maintained and installable:
#'
#' ```
#' install.packages("lidR", repos = "https://r-lidar.r-universe.dev")
#' ```
#'
#' @section What it refuses, and why:
#' The same discipline as [tile_mosaic()], for the same reason: a mixture that
#' produces a plausible-looking result nobody would question. More than one
#' vintage means overlapping returns from two flights; more than one vertical
#' datum means the ground sits at two heights in one selection.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(rgeopl_example("gleboczek_aoi.shp"))
#'
#' idx <- pointcloud_request(aoi)
#' pc <- pointcloud_get(subset(idx, year == max(year)))
#'
#' pc$path
#' pc$epsg[1]
#' }
#'
#' @seealso [pointcloud_request()] to find the tiles, [chm_get()] for a canopy
#'   model built from the published elevation models instead.
#' @export
pointcloud_get <- function(index, allow_mixed = FALSE, overwrite = FALSE,
                           max_active = NULL, quiet = FALSE) {
  if (!is.data.frame(index) || nrow(index) == 0L) {
    stop("`index` must be a non-empty index from pointcloud_request().",
         call. = FALSE)
  }
  if (!allow_mixed) check_one_survey(index)

  got <- tile_download(index, overwrite = overwrite, max_active = max_active,
                       quiet = quiet)
  got <- repair_cloud_names(got, quiet)

  keep <- !is.na(got$path) & is_cloud_file(got$path)
  if (!any(keep)) {
    stop("None of the downloaded files is a point cloud.", call. = FALSE)
  }
  out <- got[keep, , drop = FALSE]
  out$epsg <- index_epsg(index)

  say(quiet, "  ", nrow(out), " tile", if (nrow(out) == 1L) "" else "s",
      " in EPSG:", out$epsg[1], ", which the files themselves do not state")
  out
}

# One survey, or the catalogue describes a place that never existed at any
# single moment.
check_one_survey <- function(index) {
  columns <- c(year = "vintage", VRS = "vertical datum", CRS = "coordinate system")
  problems <- character(0)
  for (col in names(columns)) {
    if (!(col %in% names(index))) next
    vals <- unique(stats::na.omit(as.character(index[[col]])))
    if (length(vals) > 1L) {
      problems <- c(problems, paste0(columns[[col]], ": ",
                                     paste(sort(vals), collapse = ", ")))
    }
  }
  if (length(problems)) {
    stop(
      "These tiles are not one survey. They disagree on\n  - ",
      paste(problems, collapse = "\n  - "),
      "\nFilter the index to one of each, or pass allow_mixed = TRUE if the ",
      "mixture is deliberate.",
      call. = FALSE
    )
  }
  invisible(index)
}

is_cloud_file <- function(path) {
  file.exists(path) && !dir.exists(path) &&
    grepl("[.](laz|las)$", path, ignore.case = TRUE)
}

# A cache filled before the extension was carried over from the URL holds
# these tiles under bare names. The files are sound -- they begin with LASF --
# but lidR decides by the name and answers "File not supported", so they are
# renamed in place rather than skipped. They are ours to rename, and the
# manifest is corrected so the next run finds them without fetching again.
repair_cloud_names <- function(got, quiet = FALSE) {
  bare <- which(!is.na(got$path) & !is_cloud_file(got$path) & is_las_content(got$path))
  if (length(bare) == 0L) return(got)

  renamed <- vapply(bare, function(i) with_url_extension(got$path[i], got$URL[i]),
                    character(1))
  ok <- file.rename(got$path[bare], renamed)
  if (!any(ok)) return(got)

  rel <- substring(renamed[ok], nchar(cache_dir()) + 2L)
  cache_record_many(got$URL[bare][ok], rel, basename(dirname(rel)))
  got$path[bare[ok]] <- renamed[ok]
  say(quiet, "  renamed ", sum(ok), " cached tile",
      if (sum(ok) == 1L) "" else "s", " so lidR will open them")
  got
}

is_las_content <- function(paths) {
  vapply(paths, function(p) {
    if (!file.exists(p) || dir.exists(p)) return(FALSE)
    identical(readBin(p, "raw", n = 4L), charToRaw("LASF"))
  }, logical(1), USE.NAMES = FALSE)
}
