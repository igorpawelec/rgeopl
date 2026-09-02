# A minimal FeatureCollection, enough for sf::st_read to parse.
geojson_points <- function(n) {
  if (n == 0L) return('{"type":"FeatureCollection","features":[]}')
  feats <- paste0(
    '{"type":"Feature","properties":{"i":', seq_len(n),
    '},"geometry":{"type":"Point","coordinates":[19.0,52.0]}}',
    collapse = ",")
  paste0('{"type":"FeatureCollection","features":[', feats, ']}')
}

# Serves pages of the given sizes, in order, ignoring everything else.
pager <- function(sizes) {
  i <- 0L
  function(url, params = list(), ...) {
    i <<- i + 1L
    geojson_points(if (i <= length(sizes)) sizes[i] else 0L)
  }
}

test_that("a service that reports no total is paged until a page comes up short", {
  local_mocked_bindings(
    oapif_count = function(...) NA_integer_,
    gp_text = pager(c(3L, 3L, 1L))
  )
  out <- oapif_items("https://example.org", "things", page = 3, quiet = TRUE)
  expect_equal(nrow(out), 7L)
})

test_that("an empty first page ends it rather than looping", {
  local_mocked_bindings(
    oapif_count = function(...) NA_integer_,
    gp_text = pager(0L)
  )
  expect_null(oapif_items("https://example.org", "things", page = 3,
                          quiet = TRUE))
})

test_that("without a total, max_features still stops the walk, loudly", {
  local_mocked_bindings(
    oapif_count = function(...) NA_integer_,
    gp_text = pager(rep(3L, 20))
  )
  expect_warning(
    out <- oapif_items("https://example.org", "things", page = 3,
                       max_features = 6, quiet = TRUE),
    "did not say how many"
  )
  expect_equal(nrow(out), 6L)
})

test_that("a reported total is trusted and drives the paging", {
  local_mocked_bindings(
    oapif_count = function(...) 7L,
    gp_text = pager(c(3L, 3L, 1L))
  )
  out <- oapif_items("https://example.org", "things", page = 3, quiet = TRUE)
  expect_equal(nrow(out), 7L)
})

test_that("a total that is never reached is reported as incomplete", {
  local_mocked_bindings(
    oapif_count = function(...) 99L,
    gp_text = pager(c(3L, 3L))
  )
  expect_warning(
    oapif_items("https://example.org", "things", page = 3, quiet = TRUE),
    "assembled 6"
  )
})

test_that("a request larger than the ceiling is refused before it is made", {
  local_mocked_bindings(oapif_count = function(...) 500000L)
  expect_error(
    oapif_items("https://example.org", "things", max_features = 2e5,
                quiet = TRUE),
    class = "rgeopl_too_large"
  )
})

test_that("parts that disagree on their columns are bound, not refused", {
  skip_if_not_installed("sf")
  pt <- function(...) {
    sf::st_sf(..., geometry = sf::st_sfc(sf::st_point(c(19, 52)), crs = 4326))
  }
  p1 <- pt(id = 1L, name = "A", area = 1.5)
  p2 <- pt(id = 2L, name = "B")
  p3 <- pt(id = 3L, area = 3, note = "late")

  # This is the failure rbind_sf() exists for.
  expect_error(rbind(p1, p2))

  out <- rbind_sf(list(p1, p2, p3))
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 3L)
  expect_equal(names(out), c("id", "name", "area", "note", "geometry"))
  expect_equal(out$name, c("A", "B", NA))
  expect_equal(out$area, c(1.5, NA, 3))
  expect_equal(out$note, c(NA, NA, "late"))
  expect_equal(sf::st_crs(out), sf::st_crs(4326))
  expect_null(rbind_sf(list()))
})

test_that("a page on which no feature has a property still binds", {
  page_json <- function(props) {
    feats <- paste0(
      '{"type":"Feature","properties":', props,
      ',"geometry":{"type":"Point","coordinates":[19.0,52.0]}}',
      collapse = ",")
    paste0('{"type":"FeatureCollection","features":[', feats, ']}')
  }
  pages <- list(
    page_json(c('{"i":1,"name":"A"}', '{"i":2,"name":"B"}')),
    page_json(c('{"i":3}', '{"i":4}')),
    page_json('{"i":5,"name":"E"}')
  )
  k <- 0L
  local_mocked_bindings(
    oapif_count = function(...) 5L,
    gp_text = function(...) { k <<- k + 1L; pages[[k]] }
  )
  out <- oapif_items("https://example.org", "things", page = 2, quiet = TRUE)
  expect_equal(nrow(out), 5L)
  expect_equal(out$i, 1:5)
  expect_equal(out$name, c("A", "B", NA, NA, "E"))
})
