# A small raster with known values, shared by the tests that need one.

grid <- function(vals, nrows = 4, ncols = 4, xmin = 0, xmax = 4,
                 ymin = 0, ymax = 4, crs = "EPSG:2180") {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = nrows, ncols = ncols, xmin = xmin, xmax = xmax,
                   ymin = ymin, ymax = ymax, crs = crs)
  terra::values(r) <- vals
  r
}
