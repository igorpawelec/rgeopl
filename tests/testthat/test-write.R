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

test_that("a byte raster keeps its brightest pixels", {
  skip_if_not_installed("terra")
  # terra marks 255 as the missing value on a byte band, and in an orthophoto
  # 255 is sky and bright roofs: written that way they read back as NA
  r <- terra::rast(nrows = 20, ncols = 20, crs = "EPSG:2180")
  terra::values(r) <- c(rep(255L, 100), rep(7L, 300))

  f <- tempfile(fileext = ".tif")
  write_raster(r, f)
  back <- terra::rast(f)

  expect_equal(sum(terra::values(back) == 255, na.rm = TRUE), 100L)
  expect_equal(sum(is.na(terra::values(back))), 0L)
  expect_equal(unique(terra::datatype(back)), "INT1U")
})

test_that("a raster with gaps keeps them, and the wider type that holds them", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 20, ncols = 20, crs = "EPSG:2180")
  terra::values(r) <- c(rep(255L, 100), rep(NA_integer_, 100), rep(7L, 200))

  f <- tempfile(fileext = ".tif")
  write_raster(r, f)
  back <- terra::rast(f)

  expect_equal(sum(is.na(terra::values(back))), 100L)
  expect_equal(sum(terra::values(back) == 255, na.rm = TRUE), 100L)
  # the narrowing is skipped: something has to represent the gaps
  expect_false(identical(unique(terra::datatype(back)), "INT1U"))
})

test_that("the narrow type is the smallest the values fit in", {
  skip_if_not_installed("terra")
  byte <- terra::rast(nrows = 4, ncols = 4); terra::values(byte) <- 0:15
  expect_equal(narrow_type(byte), "INT1U")

  wide <- terra::rast(nrows = 4, ncols = 4); terra::values(wide) <- seq(0, 60000, length.out = 16)
  expect_equal(narrow_type(wide), "INT2U")

  huge <- terra::rast(nrows = 4, ncols = 4); terra::values(huge) <- seq(0, 1e7, length.out = 16)
  expect_null(narrow_type(huge))

  # negatives have no unsigned type to narrow into
  neg <- terra::rast(nrows = 4, ncols = 4); terra::values(neg) <- -8:7
  expect_null(narrow_type(neg))
})

test_that("floating point is left to terra", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 10, ncols = 10, crs = "EPSG:2180")
  terra::values(r) <- runif(100, 100, 200)
  f <- tempfile(fileext = ".tif")
  write_raster(r, f)
  expect_equal(unique(terra::datatype(terra::rast(f))), "FLT4S")
})

test_that("missing values are found wherever they are", {
  skip_if_not_installed("terra")
  clean <- terra::rast(nrows = 5, ncols = 5); terra::values(clean) <- 1:25
  expect_false(has_missing(clean))

  gappy <- terra::rast(nrows = 5, ncols = 5); terra::values(gappy) <- c(NA, 2:25)
  expect_true(has_missing(gappy))

  # and in a layer that is not the first one
  expect_true(has_missing(c(clean, gappy)))
})

test_that("a range the raster has not been asked for is computed, not given up on", {
  skip_if_not_installed("terra")
  r <- terra::rast(nrows = 20, ncols = 20, crs = "EPSG:2180")
  terra::values(r) <- c(rep(255L, 100), rep(9L, 300))

  # A virtual raster -- how every mosaic here is built -- reports no range
  # until something asks for one. Left at that, the narrowing is skipped in
  # exactly the place it was written for.
  local_mocked_bindings(minmax = function(...) matrix(c(Inf, -Inf), nrow = 2),
                        .package = "terra")
  expect_equal(narrow_type(r), "INT1U")
})

test_that("a raster with no values at all is given up on, not crashed on", {
  skip_if_not_installed("terra")
  empty <- terra::rast(nrows = 10, ncols = 10, crs = "EPSG:2180")
  expect_null(narrow_type(empty))
})
