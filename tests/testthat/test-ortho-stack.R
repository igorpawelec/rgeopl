fake_ortho <- function(...) {
  base <- data.frame(
    year = integer(0), resolution = numeric(0), composition = character(0),
    sheetID = character(0), isFilled = logical(0), stringsAsFactors = FALSE
  )
  add <- function(d, year, res, comp, sheets, filled = TRUE) {
    rbind(d, data.frame(year = year, resolution = res, composition = comp,
                        sheetID = sheets, isFilled = filled,
                        stringsAsFactors = FALSE))
  }
  d <- base
  d <- add(d, 2025L, 0.25, "CIR", c("A", "B"))
  d <- add(d, 2025L, 0.25, "RGB", c("A", "B"))
  d <- add(d, 2023L, 0.05, "CIR", c("A", "B"))
  d <- add(d, 2023L, 0.05, "RGB", c("A", "B"))
  d <- add(d, 2024L, 0.25, "RGB", c("A", "B"))   # RGB only, no CIR
  d <- add(d, 2019L, 0.50, "CIR", c("A"))        # CIR only, no RGB
  d
}

test_that("only vintages with both products are paired, newest first", {
  p <- ortho_pairs(fake_ortho())
  expect_equal(p$year, c(2025L, 2023L))
  expect_equal(p$resolution, c(0.25, 0.05))
  expect_true(all(p$CIR > 0 & p$RGB > 0))
  expect_false(2024L %in% p$year)   # RGB alone
  expect_false(2019L %in% p$year)   # CIR alone
})

test_that("an index with no pairing gives an empty table, not an error", {
  only_rgb <- subset(fake_ortho(), composition == "RGB")
  expect_equal(nrow(ortho_pairs(only_rgb)), 0L)
})

test_that("the newest flight with both is chosen, at its finest pixel", {
  got <- pick_flight(fake_ortho(), c("CIR", "RGB"), NULL, NULL)
  expect_equal(got$year, 2025L)
  expect_equal(got$resolution, 0.25)
})

test_that("year and resolution can be pinned", {
  got <- pick_flight(fake_ortho(), c("CIR", "RGB"), 2023L, NULL)
  expect_equal(got$year, 2023L)
  expect_equal(got$resolution, 0.05)
})

test_that("asking for CIR alone opens up the CIR-only vintage", {
  got <- pick_flight(fake_ortho(), "CIR", 2019L, NULL)
  expect_equal(got$year, 2019L)
})

test_that("a vintage that cannot supply both is refused with what it does have", {
  expect_error(pick_flight(fake_ortho(), c("CIR", "RGB"), 2024L, NULL),
               "No vintage here publishes")
  expect_error(pick_flight(fake_ortho(), c("CIR", "RGB"), 1999L, NULL),
               "No orthophoto tiles left")
})

test_that("tile selection keeps one filled sheet each", {
  d <- fake_ortho()
  d <- rbind(d, data.frame(year = 2025L, resolution = 0.25, composition = "CIR",
                           sheetID = "A", isFilled = FALSE,
                           stringsAsFactors = FALSE))
  sel <- flight_tiles(d, list(year = 2025L, resolution = 0.25), "CIR")
  expect_equal(nrow(sel), 2L)
  expect_true(all(sel$isFilled))
  expect_false(any(duplicated(sel$sheetID)))
})

test_that("ortho_stack validates its input before fetching anything", {
  expect_error(ortho_stack(data.frame(x = 1)), "orthophoto index")
  expect_error(ortho_pairs(data.frame(x = 1)), "orthophoto index")
})
