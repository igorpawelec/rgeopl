test_that("grid size follows the extent and the requested resolution", {
  bb <- c(xmin = 1000, ymin = 2000, xmax = 2000, ymax = 2500)
  expect_equal(unname(wcs_grid_size(bb, 1, 5000)), c(1000, 500))
  expect_equal(unname(wcs_grid_size(bb, 0.5, 5000)), c(2000, 1000))
  expect_equal(unname(wcs_grid_size(bb, 10, 5000)), c(100, 50))
})

test_that("a partial pixel is rounded up, never down", {
  bb <- c(xmin = 0, ymin = 0, xmax = 1001, ymax = 1)
  expect_equal(unname(wcs_grid_size(bb, 10, 5000))[1], 101)
})

test_that("an extent smaller than one pixel still asks for one", {
  bb <- c(xmin = 0, ymin = 0, xmax = 0.4, ymax = 0.4)
  expect_equal(unname(wcs_grid_size(bb, 1, 100)), c(1, 1))
})

test_that("oversized requests are refused with the numbers in the message", {
  bb <- c(xmin = 0, ymin = 0, xmax = 40000, ymax = 40000)
  expect_error(wcs_grid_size(bb, 1, 2500), "40000 x 40000")
  expect_error(wcs_grid_size(bb, 1, 2500), "over the 2500 limit")
  # coarser resolution brings the same area back under the cap
  expect_silent(wcs_grid_size(bb, 20, 2500))
})

test_that("resolution is validated", {
  bb <- c(xmin = 0, ymin = 0, xmax = 100, ymax = 100)
  expect_error(wcs_grid_size(bb, 0, 2500), "positive number")
  expect_error(wcs_grid_size(bb, -1, 2500), "positive number")
  expect_error(wcs_grid_size(bb, c(1, 2), 2500), "positive number")
  expect_error(wcs_grid_size(bb, "1", 2500), "positive number")
})

test_that("every coverage is fully specified", {
  for (nm in names(WCS_COVERAGES)) {
    spec <- WCS_COVERAGES[[nm]]
    expect_length(spec, 4L)
    expect_true(all(nzchar(unlist(spec))), info = nm)
    expect_true(spec[[4]] %in% c("asc", "tif"), info = nm)
  }
  # the products the two front doors offer must all exist
  expect_true(all(c("dtm_evrf2007", "dtm_kron86", "dsm_evrf2007", "dsm_kron86")
                  %in% names(WCS_COVERAGES)))
  expect_true(all(paste0("ortho_", c("standard", "high", "true"))
                  %in% names(WCS_COVERAGES)))
})

test_that("an XML error body is rejected rather than cached as a raster", {
  f <- tempfile(fileext = ".tif")
  writeLines('<?xml version="1.0"?><ServiceExceptionReport>bad bbox</ServiceExceptionReport>', f)
  expect_error(wcs_check(f), "error instead of a raster")
  expect_false(file.exists(f))   # the bad file is removed, not left to be served
})

test_that("a real raster passes the check untouched", {
  f <- tempfile(fileext = ".tif")
  writeBin(as.raw(c(0x49, 0x49, 0x2a, 0x00, rep(0, 20))), f)
  on.exit(unlink(f))
  expect_silent(wcs_check(f))
  expect_true(file.exists(f))
})

test_that("open_raster refuses input it cannot use", {
  expect_error(open_raster("no-such-file.tif"), "one existing file")
  expect_error(open_raster(c("a.tif", "b.tif")), "one existing file")
})

test_that("a GeoTIFF is returned untouched by the converter", {
  f <- tempfile(fileext = ".tif")
  writeBin(as.raw(c(0x49, 0x49, 0x2a, 0x00, rep(0, 20))), f)
  on.exit(unlink(f))
  expect_equal(to_geotiff(f), f)
})

test_that("an ASCII grid is converted, and the result carries the CRS", {
  skip_if_not_installed("terra")
  dir <- withr::local_tempdir()
  asc <- file.path(dir, "grid.asc")

  r <- terra::rast(nrows = 20, ncols = 20, xmin = 570000, xmax = 570200,
                   ymin = 150000, ymax = 150200, crs = "EPSG:2180")
  terra::values(r) <- seq_len(400)
  terra::writeRaster(r, asc, filetype = "AAIGrid")

  # an ASCII grid loses the projection on the way out; that is the problem
  expect_true(is.na(terra::crs(terra::rast(asc), describe = TRUE)$code))

  tif <- to_geotiff(asc, quiet = TRUE)
  expect_equal(tools::file_ext(tif), "tif")
  expect_true(file.exists(tif))
  expect_equal(terra::crs(terra::rast(tif), describe = TRUE)$code, "2180")
  expect_equal(terra::values(terra::rast(tif))[, 1], seq_len(400))

  # the original stays, because the cache records the file that was downloaded
  expect_true(file.exists(asc))
})

test_that("an existing conversion is reused rather than rewritten", {
  skip_if_not_installed("terra")
  dir <- withr::local_tempdir()
  asc <- file.path(dir, "grid.asc")
  r <- terra::rast(nrows = 5, ncols = 5, xmin = 0, xmax = 5, ymin = 0, ymax = 5,
                   crs = "EPSG:2180")
  terra::values(r) <- 1:25
  terra::writeRaster(r, asc, filetype = "AAIGrid")

  tif <- to_geotiff(asc, quiet = TRUE)
  stamp <- file.mtime(tif)
  expect_equal(to_geotiff(asc, quiet = TRUE), tif)
  expect_equal(file.mtime(tif), stamp)
})
