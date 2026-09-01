#' Open a downloaded raster, with its coordinate system attached
#'
#' A convenience for the one sharp edge in the coverage services: the elevation
#' models that come back as ASCII grids carry no projection information at all.
#' `terra::rast()` opens them with a CRS of `NA`, and everything afterwards --
#' overlays, distances, writing back out -- silently works in unknown units.
#' The `.prj` sidecar that would normally fix that is not read by GDAL's ASCII
#' grid driver, so the CRS is stamped here instead.
#'
#' GeoTIFFs already carry their CRS and pass through untouched.
#'
#' @param path Path returned by [dem_get()] or [ortho_get()].
#' @param crs CRS to assume when the file carries none. Defaults to EPSG:2180,
#'   which is what these services deliver.
#'
#' @return A `terra::SpatRaster`.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(c(16.93, 52.41), buffer = 300)
#'
#' terrain <- open_raster(dem_get(aoi, "dtm"))
#' surface <- open_raster(dem_get(aoi, "dsm"))
#' canopy <- surface - terrain
#' terra::plot(canopy)
#' }
#'
#' @export
open_raster <- function(path, crs = 2180) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is needed to open rasters. Install it first.",
         call. = FALSE)
  }
  if (length(path) != 1L || !file.exists(path)) {
    stop("`path` must point at one existing file.", call. = FALSE)
  }
  r <- terra::rast(path)
  if (is.na(terra::crs(r, describe = TRUE)$code) && !is.null(crs)) {
    terra::crs(r) <- paste0("EPSG:", crs)
  }
  r
}

# Writing rasters --------------------------------------------------------------
#
# Every raster this package writes goes out the same way, because the default
# was worse and nobody had chosen it. Measured on a 2369 x 2114 float tile:
# LZW with no predictor -- terra's default, and what these functions used to
# write -- 11.2 MB against 8.3 MB for DEFLATE with the right predictor, in the
# same 0.8 s. ZLEVEL=9 saves a further 2% for noticeably more work and is left
# alone. Tiling is a smaller gain, 8.3 MB to 7.8 MB and a slightly quicker
# window read, which suits a package whose usual next move is to cut a piece
# out of a large raster.
#
# The predictor is not a free choice. PREDICTOR=3 is horizontal differencing
# for floating point, and GDAL refuses it on integers outright -- "PREDICTOR=3
# is only supported with Float32 or Float64", a failed write, which is what a
# single blanket setting would have done to every orthophoto. PREDICTOR=2 on
# floats is accepted but worse, 866 KB against 808 KB on the same raster, and
# that is what the masking path was quietly doing to elevation models.
#
# The type is read with terra::is.int() rather than terra::datatype(), which
# is empty for a raster still in memory -- a canopy model just subtracted, for
# instance. is.int() is also the test terra itself uses to pick the type it
# writes, so the predictor follows the same decision.
raster_gdal <- function(x, gdal = NULL) {
  if (!is.null(gdal)) return(gdal)
  c("COMPRESS=DEFLATE",
    paste0("PREDICTOR=", if (all(terra::is.int(x))) 2L else 3L),
    "TILED=YES",
    # A national mosaic can pass the 4 GB a plain GeoTIFF can address.
    "BIGTIFF=IF_SAFER")
}

# One place where a raster is written, so the options and the missing-value
# tag are decided together -- they are not independent.
#
# terra writes a byte raster with NoData = 255, and 255 in an orthophoto is
# sky, a bright roof, saturated sand. Written that way and read back, every
# one of those pixels is NA: measured, 20 pixels of 255 in, 0 out and 20 NAs.
# Where the raster has nothing missing to mark, the tag is left off and all
# 256 values survive. Where it does have gaps -- a masked mosaic -- terra
# widens the type to hold a value outside the byte range, which costs about a
# quarter more on disk and is the right trade.
#
# The check is a full scan, so it is made only for integer rasters, which are
# the only ones the byte problem can reach. Measured at 0.36 s against a 0.80 s
# write on 48 million cells.
write_raster <- function(x, filename, gdal = NULL) {
  args <- list(x, filename, overwrite = TRUE, gdal = raster_gdal(x, gdal))
  narrow <- if (all(terra::is.int(x)) && !has_missing(x)) narrow_type(x) else NULL
  if (!is.null(narrow)) {
    args$datatype <- narrow
    args$NAflag <- NA
  }
  do.call(terra::writeRaster, args)
}

has_missing <- function(x) {
  counts <- suppressWarnings(terra::global(x, fun = "isNA"))
  any(unlist(counts, use.names = FALSE) > 0, na.rm = TRUE)
}

# The smallest unsigned type the values fit in, or NULL to let terra decide.
# Both halves of the answer are needed together: asked for no missing-value tag
# but not for a type, terra widens a byte raster to 32 bits, because that is
# where it would otherwise have put the tag. Named explicitly, the values stay
# in a byte and all 256 of them survive.
narrow_type <- function(x) {
  rng <- suppressWarnings(terra::minmax(x))
  lo <- suppressWarnings(min(rng, na.rm = TRUE))
  hi <- suppressWarnings(max(rng, na.rm = TRUE))
  if (!is.finite(lo) || !is.finite(hi) || lo < 0) return(NULL)
  if (hi <= 255) "INT1U" else if (hi <= 65535) "INT2U" else NULL
}
