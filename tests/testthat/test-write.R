test_that("floating point gets the floating point predictor, integers do not", {
  skip_if_not_installed("terra")
  f <- terra::rast(nrows = 4, ncols = 4); terra::values(f) <- runif(16, 100, 200)
  i <- terra::rast(nrows = 4, ncols = 4); terra::values(i) <- sample(0:255, 16, TRUE)

  expect_true("PREDICTOR=3" %in% raster_gdal(f))
  expect_true("PREDICTOR=2" %in% raster_gdal(i))

  # GDAL refuses PREDICTOR=3 on integers outright, so this is not cosmetic
  expect_false("PREDICTOR=3" %in% raster_gdal(i))
})

test_that("a stack is judged as a whole, since the file has one type", {
  skip_if_not_installed("terra")
  i <- terra::rast(nrows = 4, ncols = 4); terra::values(i) <- sample(0:255, 16, TRUE)
  f <- terra::rast(nrows = 4, ncols = 4); terra::values(f) <- runif(16, 0, 1)

  expect_true("PREDICTOR=2" %in% raster_gdal(c(i, i)))
  # one floating point layer makes the file floating point
  expect_true("PREDICTOR=3" %in% raster_gdal(c(i, f)))
})

test_that("every write is DEFLATE, tiled, and safe about size", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 4, ncols = 4); terra::values(r) <- 1:16
  opts <- raster_gdal(r)
  expect_true("COMPRESS=DEFLATE" %in% opts)
  expect_true("TILED=YES" %in% opts)
  expect_true("BIGTIFF=IF_SAFER" %in% opts)
})

test_that("options given by the caller replace ours rather than joining them", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 4, ncols = 4); terra::values(r) <- 1:16
  expect_equal(raster_gdal(r, "COMPRESS=NONE"), "COMPRESS=NONE")
  expect_false("COMPRESS=DEFLATE" %in% raster_gdal(r, c("COMPRESS=LZW")))
})

test_that("what comes out is what the options said, on a real file", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 200, ncols = 200, xmin = 0, xmax = 200, ymin = 0,
                   ymax = 200, crs = "EPSG:2180")
  terra::values(r) <- runif(40000, 100, 200)
  names(r) <- "elevation"

  path <- tempfile(fileext = ".tif")
  terra::writeRaster(r, path, overwrite = TRUE, gdal = raster_gdal(r))
  info <- terra::describe(path)

  expect_true(any(grepl("COMPRESSION=DEFLATE", info)))
  expect_true(any(grepl("Block=", info)))
  expect_equal(terra::crs(terra::rast(path), describe = TRUE)$code, "2180")
  expect_equal(names(terra::rast(path)), "elevation")
})
