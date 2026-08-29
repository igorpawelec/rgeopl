# Point clouds ----------------------------------------------------------------
#
# Where the rest of the package hands back a raster, this hands back a
# catalogue: `lidR` does the normalising, segmenting and metrics far better
# than anything written here would, so the job is to get its input right and
# then get out of the way.
#
# Getting it right means one thing in particular. The archive's own files
# disagree about their coordinate system: read straight out of the LAS
# headers, a 2024 tile carries a GeoKey saying EPSG:2180, while 2012 and 2014
# tiles carry a projection record three bytes long, which is to say empty.
# The index knows the answer for all of them, so it supplies what the file
# does not -- and leaves alone what the file does. It is the same rule
# `read_tile()` follows for ASCII grids, for the same reason.

#' Point cloud tiles as a catalogue ready for lidR
#'
#' Downloads what an index points at and returns it as a `lidR::LAScatalog`,
#' with the coordinate system attached. The pair to [tile_mosaic()]: that one
#' ends the raster chain, this one ends the point cloud chain.
#'
#' Everything after this is `lidR`'s: `lidR::clip_roi()` to cut to a stand,
#' `lidR::rasterize_canopy()` for a canopy model at the density the cloud
#' actually supports, `lidR::normalize_height()`, `lidR::segment_trees()`.
#'
#' @param index A point cloud index from [pointcloud_request()], filtered to
#'   what you want. It must describe one survey -- see below.
#' @param filter,select Passed to `lidR::readLAScatalog()`, and worth setting
#'   here rather than later: both are applied as the points are read, so
#'   `filter = "-drop_class 7"` never loads the noise class at all. See
#'   `lidR::readLAS()` for the vocabulary.
#' @param allow_mixed Build a catalogue from more than one survey. Off by
#'   default: two flights over one place means returns from both in the same
#'   cloud, which inflates density, doubles the canopy surface and puts two
#'   ground levels under it.
#' @param overwrite,max_active,quiet Passed to [tile_download()].
#'
#' @return A `lidR::LAScatalog`.
#'
#' @section Getting lidR:
#' `lidR` is not on CRAN. It was archived on 2026-06-09 along with `rlas`,
#' the package it reads LAS and LAZ files through, after sanitiser reports
#' went uncorrected. Both are still developed at <https://github.com/r-lidar>
#' and install from source:
#'
#' ```
#' remotes::install_github("r-lidar/rlas")
#' remotes::install_github("r-lidar/lidR")
#' ```
#'
#' Nothing else in this package needs it, and [tile_download()] will fetch
#' the same files for any other reader.
#'
#' @section What it refuses, and why:
#' The same discipline as [tile_mosaic()], for the same reason: a mixture that
#' produces a plausible-looking result nobody would question. More than one
#' vintage means overlapping returns from two flights; more than one vertical
#' datum means the ground sits at two heights in one file. Both come back as a
#' catalogue that reads perfectly and describes nothing real.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#'
#' idx <- pointcloud_request(aoi)
#' recent <- subset(idx, year == max(year))
#'
#' ctg <- pointcloud_get(recent, filter = "-drop_class 7")
#' lidR::plot(ctg)
#'
#' # a canopy model at the density the cloud supports, rather than the 1 m
#' # the coverage services publish
#' chm <- lidR::rasterize_canopy(ctg, res = 0.5, algorithm = lidR::p2r())
#' }
#'
#' @seealso [pointcloud_request()] to find the tiles, [chm_get()] for a canopy
#'   model built from the published elevation models instead.
#' @export
pointcloud_get <- function(index, filter = NULL, select = NULL,
                           allow_mixed = FALSE, overwrite = FALSE,
                           max_active = NULL, quiet = FALSE) {
  # Before anything is fetched: a point cloud selection runs to gigabytes, and
  # finding out afterwards that there is nothing here to read it with is the
  # most expensive way to learn it.
  read_catalogue <- lidR_fn("readLAScatalog")

  if (!is.data.frame(index) || nrow(index) == 0L) {
    stop("`index` must be a non-empty index from pointcloud_request().",
         call. = FALSE)
  }
  if (!allow_mixed) check_one_survey(index)

  got <- tile_download(index, overwrite = overwrite, max_active = max_active,
                       quiet = quiet)
  got <- repair_cloud_names(got, quiet)
  files <- tile_files(got, is_cloud_file)
  if (length(files) == 0L) {
    stop("None of the downloaded files is a point cloud.", call. = FALSE)
  }

  say(quiet, "Cataloguing ", length(files), " tile",
      if (length(files) == 1L) "" else "s", "...")
  ctg <- read_catalogue(files, filter = filter %||% "",
                        select = select %||% "*")
  set_cloud_crs(ctg, index_epsg(index), quiet)
}

# Older surveys leave the projection record empty, so the index fills it in.
# A file that does say what it is keeps its own answer: the two have never
# disagreed in anything measured here, and if they ever do, the file wins.
set_cloud_crs <- function(ctg, epsg, quiet = FALSE) {
  if (is.na(epsg)) return(ctg)
  if (!is.na(sf::st_crs(ctg))) return(ctg)
  sf::st_crs(ctg) <- epsg
  say(quiet, "  the tiles declare no coordinate system; took EPSG:", epsg,
      " from the index")
  ctg
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

# lidR is reached by name rather than declared in Suggests, and that is not
# fastidiousness. It left CRAN on 2026-06-09, archived along with the rlas
# package it depends on, after ASAN reports went uncorrected; both are still
# developed and pushed on GitHub. A package that names it in Suggests makes
# every continuous-integration run try to install it from a repository that
# no longer carries it, and fail there rather than here.
lidR_fn <- function(fun) {
  if (!requireNamespace("lidR", quietly = TRUE)) {
    stop("Package 'lidR' is needed to read point clouds, and it is no longer",
         " on CRAN: it was archived on 2026-06-09, together with 'rlas'.",
         "\n  Install both from source:",
         "\n    remotes::install_github(\"r-lidar/rlas\")",
         "\n    remotes::install_github(\"r-lidar/lidR\")",
         "\n  Or use tile_download() to fetch the files and read them elsewhere.",
         call. = FALSE)
  }
  getExportedValue("lidR", fun)
}
