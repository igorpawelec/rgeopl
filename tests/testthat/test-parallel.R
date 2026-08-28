sq_aoi <- function(xs, ys, buffer = 500) {
  pts <- expand.grid(x = xs, y = ys)
  as_aoi(sf::st_as_sf(pts, coords = c("x", "y"), crs = 2180), buffer = buffer)
}

test_that("a single area is never split", {
  expect_false(aoi_scattered(as_aoi(c(500000, 500000), crs = 2180, buffer = 500)))
  expect_false(aoi_scattered(as_aoi(c(4e5, 5e5, 4.1e5, 5.1e5), crs = 2180)))
})

test_that("plots far apart are recognised as scattered", {
  wide <- sq_aoi(seq(2e5, 7.8e5, length.out = 8), seq(2e5, 7e5, length.out = 5))
  expect_true(aoi_scattered(wide))
})

test_that("plots in one cluster are not", {
  tight <- sq_aoi(seq(350000, 352000, length.out = 3),
                  seq(510000, 512000, length.out = 3), buffer = 400)
  expect_false(aoi_scattered(tight))
})

test_that("the threshold is the ratio of the whole box to the parts", {
  # two plots 100 km apart: the box around them dwarfs the plots themselves
  far <- as_aoi(sf::st_as_sf(data.frame(x = c(4e5, 5e5), y = c(5e5, 5e5)),
                             coords = c("x", "y"), crs = 2180), buffer = 500)
  expect_true(aoi_scattered(far))
  expect_false(aoi_scattered(far, threshold = 1e9))
})

test_that("the connection pool is bounded at both ends", {
  expect_equal(max_active(6), 6L)
  expect_equal(max_active(0), 1L)
  expect_equal(max_active(-5), 1L)
  expect_equal(max_active(999), 16L)   # these are public services
  withr::with_options(list(rgeopl.max_active = 3), expect_equal(max_active(), 3L))
  withr::with_options(list(rgeopl.max_active = NULL), expect_equal(max_active(), 6L))
})

test_that("failures among many requests are reported, not swallowed", {
  fake <- list(
    structure(list(), class = "httr2_response"),
    simpleError("could not resolve host"),
    structure(list(), class = "httr2_response")
  )
  expect_warning(ok <- split_responses(fake, quiet = TRUE, what = "downloads"),
                 "1 of 3 downloads failed")
  expect_equal(ok, c(TRUE, FALSE, TRUE))
})

test_that("all-good responses pass silently", {
  fake <- list(structure(list(), class = "httr2_response"))
  expect_silent(ok <- split_responses(fake))
  expect_true(all(ok))
})
