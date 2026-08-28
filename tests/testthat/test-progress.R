test_that("a bar is drawn only where there is more than one step", {
  expect_null(pb_new(1, "x"))
  expect_null(pb_new(0, "x"))
  expect_null(pb_new(NA_integer_, "x"))
  expect_false(is.null(pb_new(5, "{cli::pb_current}")))
})

test_that("quiet and the option both switch it off", {
  expect_null(pb_new(10, "x", quiet = TRUE))
  withr::with_options(list(rgeopl.progress = FALSE), {
    expect_null(pb_new(10, "x"))
  })
  withr::with_options(list(rgeopl.progress = TRUE), {
    expect_false(is.null(pb_new(10, "{cli::pb_current}")))
  })
})

test_that("progress_on reads both switches", {
  expect_false(progress_on(TRUE))
  expect_true(progress_on(FALSE))
  withr::with_options(list(rgeopl.progress = FALSE), {
    expect_false(progress_on(FALSE))
    expect_false(progress_on(TRUE))
  })
})

test_that("ticking and finishing a suppressed bar is harmless", {
  expect_null(pb_tick(NULL))
  expect_null(pb_done(NULL))
  expect_silent(pb_tick(NULL))
  expect_silent(pb_done(NULL))
})

test_that("say() respects quiet", {
  expect_message(say(FALSE, "something"), "something")
  expect_silent(say(TRUE, "something"))
})

test_that("queries and downloads have separate timeouts", {
  # a stalled query should give up long before a legitimate raster would
  expect_lt(getOption("rgeopl.timeout"), getOption("rgeopl.download_timeout"))
})
