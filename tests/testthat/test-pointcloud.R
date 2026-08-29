cloud_index <- function(n = 2, ...) {
  base <- data.frame(
    sheetID = paste0("S", seq_len(n)),
    product = rep("PointCloud", n),
    year = rep(2024L, n),
    format = rep("LAZ", n),
    CRS = rep("PL-1992", n),
    VRS = rep("PL-EVRF2007-NH", n),
    URL = paste0("https://example.org/", seq_len(n), ".laz"),
    filename = paste0("t", seq_len(n), ".laz"),
    stringsAsFactors = FALSE
  )
  mods <- list(...)
  for (nm in names(mods)) base[[nm]] <- mods[[nm]]
  base
}

test_that("one survey passes", {
  expect_silent(check_one_survey(cloud_index()))
})

test_that("two flights in one catalogue are refused, and named", {
  expect_error(check_one_survey(cloud_index(2, year = c(2014L, 2024L))),
               "vintage")
  expect_error(
    check_one_survey(cloud_index(2, VRS = c("PL-KRON86-NH", "PL-EVRF2007-NH"))),
    "vertical datum")
  expect_error(check_one_survey(cloud_index(2, CRS = c("PL-1992", "PL-2000:S6"))),
               "coordinate system")

  # and the message says how to proceed on purpose
  expect_error(check_one_survey(cloud_index(2, year = c(2014L, 2024L))),
               "allow_mixed")
})

test_that("the mixture check names every disagreement at once", {
  bad <- cloud_index(2, year = c(2014L, 2024L),
                     VRS = c("PL-KRON86-NH", "PL-EVRF2007-NH"))
  msg <- tryCatch(check_one_survey(bad), error = conditionMessage)
  expect_match(msg, "vintage")
  expect_match(msg, "vertical datum")
})

test_that("a point cloud file is recognised by its extension", {
  laz <- tempfile(fileext = ".laz"); file.create(laz)
  las <- tempfile(fileext = ".LAS"); file.create(las)
  tif <- tempfile(fileext = ".tif"); file.create(tif)

  expect_true(is_cloud_file(laz))
  expect_true(is_cloud_file(las))       # the archive is inconsistent about case
  expect_false(is_cloud_file(tif))
  expect_false(is_cloud_file(tempfile(fileext = ".laz")))   # never written
  expect_false(is_cloud_file(tempdir()))
})

test_that("an empty index is refused before anything is fetched", {
  skip_if_not_installed("lidR")
  expect_error(pointcloud_get(cloud_index(0)), "non-empty")
})

test_that("without lidR the failure says so, and says what to do instead", {
  skip_if(requireNamespace("lidR", quietly = TRUE),
          "lidR is installed, so this path cannot be reached")
  expect_error(pointcloud_get(cloud_index()), "lidR")
  expect_error(pointcloud_get(cloud_index()), "tile_download")
})

test_that("a tile cached under a bare name is renamed rather than skipped", {
  dir <- file.path(tempdir(), paste0("pc-", as.integer(runif(1, 1, 1e9))))
  withr::local_options(list(rgeopl.cache_dir = dir))
  withr::defer(unlink(dir, recursive = TRUE))
  root <- cache_dir()

  bare <- file.path(root, "files", "pointcloud", "abc123_6017_N-34-79")
  dir.create(dirname(bare), recursive = TRUE, showWarnings = FALSE)
  writeBin(c(charToRaw("LASF"), as.raw(rep(0, 60))), bare)

  got <- data.frame(URL = "https://example.org/6017_N-34-79.laz", path = bare,
                    extracted = NA_character_, stringsAsFactors = FALSE)
  expect_false(is_cloud_file(bare))       # as lidR sees it: not a point cloud

  fixed <- repair_cloud_names(got, quiet = TRUE)
  expect_match(fixed$path, "[.]laz$")
  expect_true(is_cloud_file(fixed$path))
  expect_false(file.exists(bare))

  # and the manifest points at the new name, so nothing is fetched again
  expect_equal(basename(cache_lookup_many(got$URL)), basename(fixed$path))
})

test_that("files that are already named properly are left alone", {
  ok <- tempfile(fileext = ".laz")
  writeBin(c(charToRaw("LASF"), as.raw(rep(0, 60))), ok)
  got <- data.frame(URL = "https://example.org/a.laz", path = ok,
                    extracted = NA_character_, stringsAsFactors = FALSE)
  expect_equal(repair_cloud_names(got, quiet = TRUE)$path, ok)
})

test_that("something that is not a point cloud is not renamed into one", {
  tif <- tempfile()
  writeBin(as.raw(c(0x49, 0x49, 0x2a, 0x00, rep(0, 20))), tif)
  got <- data.frame(URL = "https://example.org/a.laz", path = tif,
                    extracted = NA_character_, stringsAsFactors = FALSE)
  expect_equal(repair_cloud_names(got, quiet = TRUE)$path, tif)
})
