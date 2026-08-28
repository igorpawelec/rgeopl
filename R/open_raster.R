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
