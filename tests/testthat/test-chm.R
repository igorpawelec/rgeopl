test_that("the canopy model is the difference, and is named", {
  s <- grid(rep(110, 16))
  t <- grid(rep(100, 16))
  chm <- chm_build(s, t, quiet = TRUE)
  expect_equal(unique(terra::values(chm)[, 1]), 10)
  expect_equal(names(chm), "canopy_height")
})

test_that("min_height drops cells rather than flattening them", {
  s <- grid(c(rep(105, 8), rep(99, 8)))
  t <- grid(rep(100, 16))
  chm <- chm_build(s, t, min_height = 0, quiet = TRUE)
  v <- terra::values(chm)[, 1]

  expect_equal(sum(is.na(v)), 8L)          # the negatives are gone
  expect_equal(unique(v[!is.na(v)]), 5)    # and nothing was set to zero
  expect_false(any(v == 0, na.rm = TRUE))
})

test_that("min_height is validated", {
  s <- grid(rep(110, 16)); t <- grid(rep(100, 16))
  expect_error(chm_build(s, t, min_height = "0"), "single number")
  expect_error(chm_build(s, t, min_height = c(0, 1)), "single number")
})

test_that("keep = 'all' hands back what went in", {
  s <- grid(rep(110, 16)); t <- grid(rep(100, 16))
  out <- chm_build(s, t, keep = "all", quiet = TRUE)
  expect_named(out, c("chm", "surface", "terrain"))
  expect_s4_class(out$surface, "SpatRaster")
})

test_that("matching grids pass the check", {
  expect_true(check_same_grid(grid(rep(1, 16)), grid(rep(2, 16))))
})

test_that("every kind of mismatch is caught and named", {
  s <- grid(rep(1, 16))

  expect_error(check_same_grid(s, grid(rep(1, 4), nrows = 2, ncols = 2)),
               "size")
  expect_error(check_same_grid(s, grid(rep(1, 16), xmax = 8, ymax = 8)),
               "resolution")
  expect_error(check_same_grid(s, grid(rep(1, 16), xmin = 100, xmax = 104,
                                       ymin = 100, ymax = 104)),
               "extent")
  expect_error(check_same_grid(s, grid(rep(1, 16), crs = "EPSG:4326")),
               "coordinate system")
})

test_that("a mismatch names every problem at once", {
  s <- grid(rep(1, 16))
  t <- grid(rep(1, 4), nrows = 2, ncols = 2, xmin = 50, xmax = 54,
            ymin = 50, ymax = 54)
  msg <- tryCatch(check_same_grid(s, t), error = conditionMessage)
  expect_match(msg, "size")
  expect_match(msg, "extent")
})

test_that("inputs may be rasters or paths, and nothing else", {
  r <- grid(rep(1, 16))
  expect_s4_class(as_raster(r), "SpatRaster")
  expect_error(as_raster(42), "Expected a file path or a SpatRaster")
  expect_error(as_raster(list()), "Expected a file path or a SpatRaster")
})

test_that("mask needs an area to cut to", {
  s <- grid(rep(110, 16)); t <- grid(rep(100, 16))
  expect_error(chm_build(s, t, mask = TRUE, quiet = TRUE), "needs an `aoi`")
})

test_that("masking cuts to the outline, not the bounding box", {
  skip_if_not_installed("terra")
  s <- grid(rep(110, 100), nrows = 10, ncols = 10, xmax = 10, ymax = 10)
  t <- grid(rep(100, 100), nrows = 10, ncols = 10, xmax = 10, ymax = 10)

  # a circle inside the square leaves about 1 - pi/4 of it outside
  circle <- as_aoi(sf::st_sfc(sf::st_point(c(5, 5)), crs = 2180), buffer = 5)
  out <- chm_build(s, t, aoi = circle, mask = TRUE, quiet = TRUE)
  share <- mean(is.na(terra::values(out)[, 1]))
  expect_gt(share, 0.1)
  expect_lt(share, 0.35)

  # and without it nothing is dropped
  plain <- chm_build(s, t, quiet = TRUE)
  expect_equal(sum(is.na(terra::values(plain)[, 1])), 0L)
})

test_that("the raster CRS is read as a number sf will accept", {
  skip_if_not_installed("terra")
  r <- grid(rep(1, 16))
  expect_type(raster_epsg(r), "integer")
  expect_equal(raster_epsg(r), 2180L)
  expect_silent(sf::st_crs(raster_epsg(r)))

  # a raster with no CRS falls back rather than erroring
  bare <- terra::rast(nrows = 2, ncols = 2, xmin = 0, xmax = 2, ymin = 0, ymax = 2)
  terra::values(bare) <- 1:4
  expect_equal(raster_epsg(bare), CRS_PL1992)
})

# Building from the archive ---------------------------------------------------

dem_index <- function(...) {
  base <- data.frame(
    sheetID = c("A", "B", "A", "B"),
    year = rep(2014L, 4),
    product = c("DSM", "DSM", "DTM", "DTM"),
    resolution = rep(1, 4),
    isFilled = rep(TRUE, 4),
    stringsAsFactors = FALSE
  )
  mods <- list(...)
  for (nm in names(mods)) base[[nm]] <- mods[[nm]]
  base
}

test_that("a vintage holding both models is usable, one holding half is not", {
  expect_equal(both_products(dem_index()), 1)

  # a terrain model with no surface model of the same year makes no canopy
  terrain_only <- dem_index(product = rep("DTM", 4))
  expect_length(both_products(terrain_only), 0L)
})

test_that("the pixel size is settled once for the pair", {
  # 1 m has both models, 0.5 m has only the terrain
  mixed <- data.frame(
    sheetID = c("A", "A", "A"), year = rep(2014L, 3),
    product = c("DSM", "DTM", "DTM"), resolution = c(1, 1, 0.5),
    isFilled = rep(TRUE, 3), stringsAsFactors = FALSE
  )
  expect_equal(both_products(mixed), 1)

  # so the finer size is not chosen just because it is finer
  pair <- chm_pair(mixed, year = 2014, resolution = NULL)
  expect_equal(pair$resolution, 1)
  expect_equal(nrow(pair$surface), 1L)
  expect_equal(nrow(pair$terrain), 1L)
})

test_that("an asked-for pixel size is honoured when the archive has it", {
  both <- data.frame(
    sheetID = rep("A", 4), year = rep(2014L, 4),
    product = c("DSM", "DTM", "DSM", "DTM"), resolution = c(1, 1, 0.5, 0.5),
    isFilled = rep(TRUE, 4), stringsAsFactors = FALSE
  )
  expect_equal(chm_pair(both, 2014, resolution = 1)$resolution, 1)
  expect_equal(chm_pair(both, 2014, resolution = 0.5)$resolution, 0.5)
  # and one it does not have falls back to the finest it does
  expect_equal(chm_pair(both, 2014, resolution = 2)$resolution, 0.5)
})

test_that("a year the archive cannot pair up is refused, pointing at chm_years()", {
  expect_error(chm_pair(dem_index(product = rep("DTM", 4)), 2014, NULL),
               "chm_years")
  expect_error(chm_pair(dem_index(), 1999, NULL), "no vintage from 1999")
})

test_that("only one row per sheet survives, and a filled sheet beats an empty one", {
  dup <- dem_index(sheetID = c("A", "A", "A", "A"),
                   isFilled = c(FALSE, TRUE, TRUE, TRUE))
  expect_equal(nrow(one_per_sheet(dup)), 1L)
  expect_true(one_per_sheet(dup)$isFilled)
})
