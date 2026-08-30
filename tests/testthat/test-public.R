# The functions people actually type. Their internals are covered elsewhere;
# this is about the entry points holding their shape -- argument order, return
# value, the promise on the help page.

test_that("is_aoi() recognises what as_aoi() makes, and nothing else", {
  expect_true(is_aoi(as_aoi(c(16.93, 52.41))))
  expect_false(is_aoi(c(16.93, 52.41)))
  expect_false(is_aoi(NULL))
  expect_false(is_aoi(sf::st_sfc(sf::st_point(c(16.93, 52.41)), crs = 4326)))
})

test_that("aoi_geom() hands back geometry in the system asked for", {
  aoi <- as_aoi(c(16.93, 52.41))

  # PL-1992 by default, whatever went in
  g <- aoi_geom(aoi)
  expect_s3_class(g, "sfc")
  expect_equal(sf::st_crs(g)$epsg, 2180L)

  expect_equal(sf::st_crs(aoi_geom(aoi, crs = 4326))$epsg, 4326L)
  expect_equal(sf::st_crs(aoi_geom(aoi, crs = 2177))$epsg, 2177L)

  # and it accepts anything as_aoi() would, not only an aoi
  expect_equal(sf::st_crs(aoi_geom(c(16.93, 52.41)))$epsg, 2180L)
})

test_that("aoi_geom(crs = NULL) leaves the geometry where it was", {
  aoi <- as_aoi(c(16.93, 52.41))
  expect_equal(sf::st_crs(aoi_geom(aoi, crs = NULL))$epsg, 4326L)
})

test_that("cache_set_dir() moves the cache and reports where to", {
  old <- getOption("rgeopl.cache_dir")
  withr::defer(options(rgeopl.cache_dir = old))

  dir <- file.path(tempdir(), paste0("moved-", as.integer(runif(1, 1, 1e9))))
  withr::defer(unlink(dir, recursive = TRUE))

  got <- cache_set_dir(dir)
  expect_equal(normalizePath(got), normalizePath(dir))
  expect_true(dir.exists(file.path(dir, "files")))
  expect_equal(getOption("rgeopl.cache_dir"), dir)
})

test_that("cache_info() returns the manifest and says the cache is empty", {
  local_cache()
  expect_message(out <- cache_info(), "empty")
  expect_equal(nrow(out), 0L)

  rel <- put("a.tif", bytes = 2048)
  cache_record_many("https://a", rel, group = "dem")
  expect_message(out <- cache_info(), "1 files")
  expect_equal(nrow(out), 1L)
  expect_equal(out$group, "dem")

  # asking about a group that holds nothing is not an error
  expect_message(expect_equal(nrow(cache_info("ortho")), 0L), "empty")
})

test_that("plot_units() draws and returns its input unchanged", {
  skip_if_not_installed("sf")
  units <- sf::st_sf(
    name = c("A", "B"),
    geometry = sf::st_sfc(
      sf::st_polygon(list(cbind(c(0, 1, 1, 0, 0), c(0, 0, 1, 1, 0)))),
      sf::st_polygon(list(cbind(c(2, 3, 3, 2, 2), c(0, 0, 1, 1, 0)))),
      crs = 2180))

  path <- tempfile(fileext = ".png")
  grDevices::png(path, width = 200, height = 200)
  out <- plot_units(units, label = "name")
  grDevices::dev.off()

  expect_identical(out, units)
  expect_gt(file.size(path), 0)
})

test_that("plot_units() refuses what it cannot draw", {
  expect_error(plot_units(data.frame(a = 1)), "must be an sf object")
  expect_error(plot_units(sf::st_sf(a = integer(0),
                                    geometry = sf::st_sfc(crs = 2180))),
               "no rows")
})
