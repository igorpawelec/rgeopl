test_that("a lon/lat point gets EPSG:4326 and a PL-1992 point gets EPSG:2180", {
  a <- as_aoi(c(16.93, 52.41))
  expect_s3_class(a, "rgeopl_aoi")
  expect_equal(a$type, "point")
  expect_equal(sf::st_crs(a$geom)$epsg, 4326L)

  b <- as_aoi(c(571248, 151377))
  expect_equal(sf::st_crs(b$geom)$epsg, 2180L)
})

test_that("coordinates outside both windows are refused rather than guessed", {
  expect_error(as_aoi(c(-120, 49)), "Cannot infer a CRS")
  expect_error(as_aoi(c(2e6, 2e6)), "Cannot infer a CRS")
})

test_that("an explicit crs overrides inference", {
  a <- as_aoi(c(16.93, 52.41), crs = 4326)
  expect_equal(sf::st_crs(a$geom)$epsg, 4326L)
})

test_that("bounding boxes are validated", {
  ok <- as_aoi(c(571248, 151377, 572248, 152377), crs = 2180)
  expect_equal(ok$type, "area")
  expect_error(as_aoi(c(572248, 151377, 571248, 152377), crs = 2180),
               "xmin <= xmax")
  expect_error(as_aoi(c(1, 2, 3), crs = 2180), "length 2")
  expect_error(as_aoi(c(NA, 1), crs = 2180), "must not be NA")
})

test_that("buffering happens in metres and turns a point into an area", {
  a <- as_aoi(c(16.93, 52.41), buffer = 500)
  expect_equal(a$type, "area")
  # a 500 m buffer spans 1 km across, give or take the polygon approximation
  bb <- aoi_bbox(a)
  expect_equal(unname(bb["xmax"] - bb["xmin"]), 1000, tolerance = 0.01)
  expect_equal(unname(bb["ymax"] - bb["ymin"]), 1000, tolerance = 0.01)
})

test_that("aoi_bbox reprojects and by_feature splits", {
  a <- as_aoi(c(571248, 151377, 572248, 152377), crs = 2180)
  bb2180 <- aoi_bbox(a)
  expect_equal(unname(bb2180), c(571248, 151377, 572248, 152377))

  bb4326 <- aoi_bbox(a, crs = 4326)
  expect_true(all(bb4326[c("xmin", "xmax")] > 13 & bb4326[c("xmin", "xmax")] < 25))
  expect_true(all(bb4326[c("ymin", "ymax")] > 48 & bb4326[c("ymin", "ymax")] < 56))

  pts <- as_aoi(matrix(c(16.9, 52.4, 17.1, 52.6), ncol = 2, byrow = TRUE))
  single <- aoi_bbox(pts)
  each <- aoi_bbox(pts, by_feature = TRUE)
  expect_length(each, 2L)
  expect_true(single[["xmax"]] - single[["xmin"]] >
                each[[1]][["xmax"]] - each[[1]][["xmin"]])
})

test_that("sf, sfc and bbox inputs round-trip", {
  poly <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 571248, ymin = 151377, xmax = 572248, ymax = 152377),
    crs = sf::st_crs(2180)
  ))
  from_sfc <- as_aoi(poly)
  from_sf <- as_aoi(sf::st_sf(id = 1, geometry = poly))
  from_bbox <- as_aoi(sf::st_bbox(poly))

  expect_equal(aoi_bbox(from_sfc), aoi_bbox(from_sf))
  expect_equal(aoi_bbox(from_sfc), aoi_bbox(from_bbox))
})

test_that("WKT is accepted and nonsense strings are not", {
  a <- as_aoi("POINT (16.93 52.41)", crs = 4326)
  expect_equal(a$type, "point")
  expect_error(as_aoi("not a geometry"), "neither an existing file nor valid WKT")
})

test_that("an aoi passed back in is left alone", {
  a <- as_aoi(c(16.93, 52.41))
  expect_identical(as_aoi(a), a)
})

test_that("geometries without a CRS are refused", {
  bare <- sf::st_sfc(sf::st_point(c(16.93, 52.41)))
  expect_error(as_aoi(bare), "no CRS")
})

test_that("print stays on one screen", {
  a <- as_aoi(c(16.93, 52.41), buffer = 100)
  expect_output(print(a), "rgeopl area of interest")
  expect_output(print(a), "EPSG:2180")
})

test_that("the shipped examples exist and become valid areas of interest", {
  expect_setequal(rgeopl_example(), c("gleboczek_aoi.shp", "test_lasow.shp"))
  expect_error(rgeopl_example("nope.shp"), "No example called")

  pt <- as_aoi(sf::st_read(rgeopl_example("test_lasow.shp"), quiet = TRUE))
  expect_equal(pt$type, "point")

  poly <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
  expect_equal(poly$type, "area")
  expect_equal(length(poly$geom), 2L)
  expect_equal(sf::st_crs(poly$geom)$epsg, 2180L)
  # roughly 600 ha across the two polygons
  expect_equal(as.numeric(sum(sf::st_area(poly$geom))) / 1e4, 600, tolerance = 0.05)
})
