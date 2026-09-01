fake_dem_index <- function() {
  data.frame(product = rep("DTM", 2), year = c(2014L, 2022L),
             resolution = c(1, 1), CRS = rep("PL-1992", 2),
             VRS = c("PL-KRON86-NH", "PL-EVRF2007-NH"),
             stringsAsFactors = FALSE)
}

dem <- function(value = 100, res = 100, xmin = 600000, ymin = 700000,
                crs = "EPSG:2180") {
  r <- terra::rast(xmin = xmin, xmax = xmin + 2000, ymin = ymin,
                   ymax = ymin + 2000, resolution = res, crs = crs)
  terra::values(r) <- value
  names(r) <- "elevation"
  r
}

test_that("converting a system into itself is refused rather than done", {
  skip_if_not_installed("terra")
  expect_error(dem_to_datum(dem(), "kron86", "kron86"), "nothing to convert")
})

test_that("a raster with no coordinate system cannot be placed", {
  skip_if_not_installed("terra")
  bare <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 4, ymin = 0, ymax = 4)
  terra::values(bare) <- 100
  terra::crs(bare) <- ""
  expect_error(dem_to_datum(bare, "kron86", "evrf2007"), "no coordinate system")
})

test_that("both systems have a quasi-geoid model to go through", {
  expect_setequal(names(GEOID_GRIDS), c("kron86", "evrf2007"))
  expect_true(all(grepl("^pl_gugik_geoid.*[.]tif$", GEOID_GRIDS)))
})

test_that("the sampling lattice is coarse but never coarser than the raster", {
  skip_if_not_installed("terra")
  # a 2 km square asked for 1 km samples still gets several across it
  expect_lte(max(lattice_step(dem(), 1000)), 2000 / 3)

  # and a lattice finer than the cells themselves would be samples of nothing
  expect_equal(min(lattice_step(dem(res = 500), 10)), 500)
})

test_that("a shift that is zero everywhere is reported, not applied", {
  skip_if_not_installed("terra")
  # what a silent +proj=noop leaves behind
  local_mocked_bindings(vertical_shift = function(lon, lat, from, to) {
    rep(0, length(lon))
  })
  expect_error(dem_to_datum(dem(), "kron86", "evrf2007", quiet = TRUE),
               "no shift at all")
})

test_that("an area reaching outside the models is refused", {
  skip_if_not_installed("terra")
  local_mocked_bindings(vertical_shift = function(lon, lat, from, to) {
    z <- rep(0.16, length(lon))
    z[1] <- NA_real_
    z
  })
  expect_error(dem_to_datum(dem(), "kron86", "evrf2007", quiet = TRUE),
               "outside the")
})

test_that("the shift is added to the heights and nothing else changes", {
  skip_if_not_installed("terra")
  local_mocked_bindings(vertical_shift = function(lon, lat, from, to) {
    rep(0.165, length(lon))
  })
  r <- dem(value = 100)
  out <- dem_to_datum(r, "kron86", "evrf2007", quiet = TRUE)

  expect_equal(unique(round(terra::values(out)[, 1], 3)), 100.165)
  expect_equal(terra::res(out), terra::res(r))
  expect_equal(as.vector(terra::ext(out)), as.vector(terra::ext(r)))
  expect_equal(names(out), names(r))
})

test_that("the index spelling and the short name mean the same thing", {
  expect_equal(as_datum("PL-KRON86-NH"), "kron86")
  expect_equal(as_datum("PL-EVRF2007-NH"), "evrf2007")
  expect_equal(as_datum("kron86"), "kron86")
  expect_equal(as_datum(c("PL-KRON86-NH", "evrf2007")), c("kron86", "evrf2007"))
  expect_null(as_datum(NULL))
})

test_that("a vertical system nobody has heard of is refused, with the options", {
  expect_error(as_datum("PL-1965"), "Unknown datum")
  expect_error(as_datum("PL-1965"), "kron86")
  expect_error(as_datum("nonsense", what = "vertical datum"), "vertical datum")
})

test_that("the datums present in an index are read from its VRS column", {
  idx <- data.frame(VRS = c("PL-KRON86-NH", "PL-KRON86-NH", "PL-EVRF2007-NH"),
                    stringsAsFactors = FALSE)
  expect_equal(index_datums(idx), c("evrf2007", "kron86"))
  expect_length(index_datums(data.frame(a = 1)), 0L)
  expect_equal(index_datums(data.frame(VRS = rep("PL-KRON86-NH", 3))), "kron86")
})

test_that("a canopy model built from two systems converts before subtracting", {
  skip_if_not_installed("terra")
  s <- grid(rep(110, 16))

  # same system on both sides: nothing to do, and no network touched
  expect_identical(level_datums(s, c("kron86", "kron86"), quiet = TRUE), s)
  expect_identical(level_datums(s, NULL, quiet = TRUE), s)
  expect_identical(level_datums(s, c("PL-KRON86-NH", "kron86"), quiet = TRUE), s)
})

test_that("naming only one of the two systems is refused", {
  skip_if_not_installed("terra")
  s <- grid(rep(110, 16))
  expect_error(level_datums(s, "kron86", quiet = TRUE), "both rasters")
  expect_error(level_datums(s, c("a", "b", "c"), quiet = TRUE), "both rasters")
})

test_that("mixing datums is refused unless a target is named", {
  idx <- fake_dem_index()
  expect_error(check_mosaicable(idx), "vertical datum")

  # Two vertical systems mean two flights, so naming a datum has to accept the
  # vintages that come with them.
  expect_silent(check_mosaicable(idx, ignore = c("VRS", "year")))

  # but nothing else is waved through
  mixed <- idx; mixed$resolution <- c(1, 0.5)
  expect_error(check_mosaicable(mixed, ignore = c("VRS", "year")), "resolution")
  mixed2 <- idx; mixed2$product <- c("DTM", "DSM")
  expect_error(check_mosaicable(mixed2, ignore = c("VRS", "year")), "product")
})
