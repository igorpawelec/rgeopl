# Canopy height ---------------------------------------------------------------
#
# Surface minus terrain, which is arithmetic, and three checks around it that
# are not:
#
#   the two rasters must sit on the same grid, or the subtraction resamples one
#   of them without saying so;
#
#   they must come from the same survey, or the difference is partly the change
#   between two flights;
#
#   the vertical datum cancels -- both halves are measured in it -- so a canopy
#   model is safe across the 2019 change of datum in a way that comparing two
#   terrain models is not.

#' Canopy height for an area
#'
#' Fetches the surface and terrain models over an area and subtracts one from
#' the other. `chm_get()` downloads both; `chm_build()` does the arithmetic on
#' rasters you already have.
#'
#' @param aoi An area of interest: anything [as_aoi()] accepts.
#' @param resolution Pixel size in metres. Both models are requested at the
#'   same one, which is what puts them on the same grid.
#' @param datum Vertical reference system, `"evrf2007"` or `"kron86"`. It
#'   cancels in the subtraction, so it matters only if you also want the inputs.
#' @param keep `"chm"` returns the canopy model alone; `"all"` returns a list
#'   of all three rasters, canopy, surface and terrain, when you want to look
#'   at what went into it.
#' @param min_height Heights below this become `NA`. `NULL`, the default,
#'   changes nothing. Setting it to `0` removes the small negative values that
#'   come from noise in the two models; note that this drops those cells rather
#'   than flattening them to zero, so it does not invent ground where there was
#'   none.
#' @param mask Cut the result to the outline of the area rather than to its
#'   bounding box, so a ragged stand comes back without its corners filled
#'   in. For [chm_build()] this needs `aoi` as well.
#' @param filename Write the canopy model here.
#' @param max_pixels Passed to [dem_get()].
#' @param quiet Suppress progress.
#'
#' @return A `terra::SpatRaster`, or with `keep = "all"` a list of three named
#'   `chm`, `surface` and `terrain`.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(c(16.80, 52.44), buffer = 400)
#'
#' canopy <- chm_get(aoi, resolution = 1)
#' terra::plot(canopy)
#'
#' # keep what went into it, and drop the noise below ground
#' parts <- chm_get(aoi, keep = "all", min_height = 0)
#' terra::plot(parts$surface)
#' }
#'
#' @seealso [dem_get()] for the models on their own, and [coverage()] to check
#'   whether a canopy model is possible from the archive at all -- these
#'   coverage services publish only the current one.
#' @export
chm_get <- function(aoi, resolution = 1, datum = c("evrf2007", "kron86"),
                    keep = c("chm", "all"), min_height = NULL, mask = FALSE,
                    filename = NULL, max_pixels = 2500, quiet = FALSE) {
  datum <- match.arg(datum)
  keep <- match.arg(keep)

  say(quiet, "Surface model...")
  surface <- dem_get(aoi, "dsm", resolution = resolution, datum = datum,
                     max_pixels = max_pixels, quiet = quiet)
  say(quiet, "Terrain model...")
  terrain <- dem_get(aoi, "dtm", resolution = resolution, datum = datum,
                     max_pixels = max_pixels, quiet = quiet)

  chm_build(surface, terrain, aoi = if (isTRUE(mask)) aoi else NULL,
            keep = keep, min_height = min_height, mask = mask,
            filename = filename, quiet = quiet)
}

#' @rdname chm_get
#' @param surface,terrain Surface and terrain models: file paths, or
#'   `terra::SpatRaster` objects.
#' @param aoi The area to cut to when `mask = TRUE`. Ignored otherwise.
#' @export
chm_build <- function(surface, terrain, aoi = NULL, keep = c("chm", "all"),
                      min_height = NULL, mask = FALSE, filename = NULL,
                      quiet = FALSE) {
  keep <- match.arg(keep)
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is needed to build a canopy model. Install it first.",
         call. = FALSE)
  }
  if (!is.null(min_height) &&
      (!is.numeric(min_height) || length(min_height) != 1L)) {
    stop("`min_height` must be a single number, or NULL.", call. = FALSE)
  }

  s <- as_raster(surface)
  t <- as_raster(terrain)
  check_same_grid(s, t)

  say(quiet, "Subtracting...")
  chm <- s - t
  if (!is.null(min_height)) chm[chm < min_height] <- NA
  if (isTRUE(mask)) {
    if (is.null(aoi)) {
      stop("`mask = TRUE` needs an `aoi` to cut to.", call. = FALSE)
    }
    geom <- aoi_geom(as_aoi(aoi), crs = raster_epsg(chm))
    chm <- terra::mask(terra::crop(chm, terra::vect(geom)), terra::vect(geom))
    say(quiet, "  masked to the area outline")
  }
  names(chm) <- "canopy_height"

  if (!is.null(filename)) {
    say(quiet, "  writing ", basename(filename))
    chm <- terra::writeRaster(chm, filename, overwrite = TRUE)
  }
  if (keep == "all") {
    return(list(chm = chm, surface = s, terrain = t))
  }
  chm
}

as_raster <- function(x) {
  if (inherits(x, "SpatRaster")) return(x)
  if (is.character(x) && length(x) == 1L) return(open_raster(x))
  stop("Expected a file path or a SpatRaster, not ",
       paste(class(x), collapse = "/"), ".", call. = FALSE)
}

# terra will happily subtract rasters that do not line up, resampling one of
# them on the way and saying nothing. For a canopy model that turns a
# half-pixel offset into a rim of false height around every crown, so the
# mismatch is reported instead.
check_same_grid <- function(s, t, what = c("surface", "terrain")) {
  problems <- character(0)
  if (!identical(dim(s)[1:2], dim(t)[1:2])) {
    problems <- c(problems, sprintf(
      "size: %d x %d against %d x %d",
      terra::nrow(s), terra::ncol(s), terra::nrow(t), terra::ncol(t)))
  }
  if (!isTRUE(all.equal(terra::res(s), terra::res(t)))) {
    problems <- c(problems, sprintf(
      "resolution: %s against %s",
      paste(signif(terra::res(s), 6), collapse = " x "),
      paste(signif(terra::res(t), 6), collapse = " x ")))
  }
  if (!isTRUE(all.equal(as.vector(terra::ext(s)), as.vector(terra::ext(t)),
                        tolerance = 1e-6))) {
    problems <- c(problems, "extent: the two do not cover the same ground")
  }
  scrs <- terra::crs(s, describe = TRUE)$code
  tcrs <- terra::crs(t, describe = TRUE)$code
  if (!identical(scrs, tcrs)) {
    problems <- c(problems, sprintf("coordinate system: %s against %s",
                                    scrs %||% "none", tcrs %||% "none"))
  }
  if (length(problems)) {
    stop(
      "The ", what[1], " and ", what[2], " rasters are not on the same grid:",
      "\n  - ", paste(problems, collapse = "\n  - "),
      "\nRequest both through chm_get(), or align them yourself with ",
      "terra::resample() before subtracting.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}
