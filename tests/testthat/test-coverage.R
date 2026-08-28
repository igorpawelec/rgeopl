cov_fixture <- function() {
  sq <- function(x0, y0, s) {
    sf::st_polygon(list(cbind(c(x0, x0 + s, x0 + s, x0, x0),
                              c(y0, y0, y0 + s, y0 + s, y0))))
  }
  # 2019: two tiles covering the whole 2 x 1 km strip
  # 2024: one tile covering the left half only
  geom <- sf::st_sfc(
    sq(0, 0, 1000), sq(1000, 0, 1000), sq(0, 0, 1000),
    crs = 2180
  )
  sf::st_as_sf(data.frame(
    year = c(2019L, 2019L, 2024L),
    product = factor(c("DTM", "DTM", "DTM")),
    geometry = geom
  ))
}

cov_aoi <- function() {
  as_aoi(c(0, 0, 2000, 1000), crs = 2180)
}

test_that("coverage counts tiles and unioned area per group", {
  cv <- coverage(cov_fixture(), by = "year")
  expect_equal(cv$year, c(2019L, 2024L))
  expect_equal(cv$tiles, c(2L, 1L))
  expect_equal(cv$area_km2, c(2, 1))
  expect_false("aoi_share" %in% names(cv))
})

test_that("aoi_share is the fraction of the area actually covered", {
  cv <- coverage(cov_fixture(), by = "year", aoi = cov_aoi())
  expect_equal(cv$aoi_share, c(1, 0.5))
})

test_that("overlapping tiles are unioned, not double counted", {
  x <- cov_fixture()
  doubled <- rbind(x, x[1, ]) # same tile twice in one vintage
  cv <- coverage(doubled, by = "year", aoi = cov_aoi())
  expect_equal(cv$tiles[cv$year == 2019], 3L)
  expect_equal(cv$area_km2[cv$year == 2019], 2)
  expect_equal(cv$aoi_share[cv$year == 2019], 1)
})

test_that("the grouping column keeps its type", {
  cv <- coverage(cov_fixture(), by = "year")
  expect_type(cv$year, "integer")
  cv2 <- coverage(cov_fixture(), by = "product")
  expect_s3_class(cv2$product, "factor")
})

test_that("coverage and plot_coverage reject a column that is not there", {
  expect_error(coverage(cov_fixture(), by = "vintage"), "is not there")
  expect_error(plot_coverage(cov_fixture(), by = "vintage"), "is not there")
  expect_error(plot_coverage(cov_fixture()[0, ]), "no rows")
})

test_that("an empty index gives an empty summary rather than an error", {
  cv <- coverage(cov_fixture()[0, ], by = "year")
  expect_equal(nrow(cv), 0L)
})

test_that("both plot modes draw without error", {
  x <- cov_fixture()
  f <- tempfile(fileext = ".png")
  on.exit(unlink(f))

  grDevices::png(f)
  expect_silent(plot_coverage(x, by = "year", aoi = cov_aoi()))
  grDevices::dev.off()
  expect_true(file.size(f) > 0)

  grDevices::png(f)
  expect_silent(plot_coverage(x, by = "year", facet = FALSE))
  grDevices::dev.off()
  expect_true(file.size(f) > 0)
})

test_that("too many groups are capped with a message", {
  x <- cov_fixture()
  f <- tempfile(fileext = ".png")
  on.exit(unlink(f))
  grDevices::png(f)
  expect_message(plot_coverage(x, by = "year", max_panels = 1L),
                 "1 older ones not drawn")
  grDevices::dev.off()
})

test_that("features beside a non-rectangular area are dropped, not clipped", {
  # An L-shaped area: its bounding box contains a corner it does not cover.
  L <- sf::st_sfc(sf::st_polygon(list(cbind(
    c(0, 2000, 2000, 1000, 1000, 0, 0),
    c(0, 0, 1000, 1000, 2000, 2000, 0)
  ))), crs = 2180)
  aoi <- as_aoi(L)

  sq <- function(x0, y0, s = 800) {
    sf::st_polygon(list(cbind(c(x0, x0 + s, x0 + s, x0, x0),
                              c(y0, y0, y0 + s, y0 + s, y0))))
  }
  tiles <- sf::st_as_sf(data.frame(
    id = c("inside", "in-the-notch"),
    geometry = sf::st_sfc(sq(100, 100), sq(1150, 1150), crs = 2180)
  ))

  kept <- keep_touching_aoi(tiles, aoi)
  expect_equal(kept$id, "inside")
  # the survivor keeps its full geometry
  expect_equal(as.numeric(sf::st_area(kept)), 800^2)
})

test_that("an empty table survives the area filter", {
  aoi <- as_aoi(c(0, 0, 1000, 1000), crs = 2180)
  empty <- cov_fixture()[0, ]
  expect_equal(nrow(keep_touching_aoi(empty, aoi)), 0L)
})
