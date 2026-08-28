test_that("loose and fixed-width addresses parse identically", {
  loose <- split_address("09-01-2-10-187-f-00")
  fixed <- split_address("09-01-2-10-187   -f   -00")
  expect_equal(loose, fixed)
  expect_equal(unname(fixed[c("directorate_cd", "inspectorate_cd", "obreb_cd",
                              "range_cd", "compartment", "subarea", "part")]),
               c("09", "01", "2", "10", "187", "f", "00"))
})

test_that("a truncated address leaves the rest NA", {
  p <- split_address("04-02")
  expect_equal(unname(p[["directorate_cd"]]), "04")
  expect_equal(unname(p[["inspectorate_cd"]]), "02")
  expect_true(all(is.na(p[c("obreb_cd", "range_cd", "compartment", "subarea", "part")])))
})

test_that("surrounding and internal padding is tolerated", {
  expect_equal(split_address("  04-02-2-11  "), split_address("04-02-2-11"))
  expect_equal(split_address("04-02-2 -11"), split_address("04-02-2-11"))
})

test_that("compartments keep their letter suffix", {
  expect_equal(unname(split_address("09-02-1-06-33A-c")[["compartment"]]), "33A")
})

test_that("depth counts only the leading run of components", {
  expect_equal(address_depth(split_address("04")), 1L)
  expect_equal(address_depth(split_address("04-02")), 2L)
  expect_equal(address_depth(split_address("04-02-2")), 3L)
  expect_equal(address_depth(split_address("04-02-2-11")), 4L)
  expect_equal(address_depth(split_address("04-02-2-11-165")), 5L)
  expect_equal(address_depth(split_address("04-02-2-11-165-a")), 6L)
  # a gap stops the count rather than being treated as a wildcard
  expect_equal(address_depth(split_address("04--2-11")), 1L)
})

test_that("an empty address is rejected", {
  expect_equal(address_depth(split_address("")), 0L)
  expect_error(split_address(c("04", "05")), "single forest address")
  expect_error(split_address(NA), "single forest address")
})

test_that("address matching ignores components that were not given", {
  x <- data.frame(
    directorate_cd = c("04", "04", "09"), inspectorate_cd = c("02", "02", "01"),
    obreb_cd = c("2", "2", "1"), range_cd = c("11", "19", "02"),
    compartment = c("165", "165", "165"), subarea = c("a", "a", "a"),
    part = c("00", "00", "00"), stringsAsFactors = FALSE
  )
  parts <- split_address("04-02-2-11")
  expect_equal(which(address_match(x, parts, names(parts))), 1L)

  # compartment given without a sub-compartment matches every sub-compartment of that compartment
  parts2 <- split_address("04-02-2-11-165")
  expect_equal(which(address_match(x, parts2, names(parts2))), 1L)
})
