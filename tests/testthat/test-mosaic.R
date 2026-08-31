fake_index <- function(n = 3, ...) {
  base <- data.frame(
    product = factor(rep("Orthophoto", n)),
    year = rep(2025L, n),
    composition = rep("RGB", n),
    resolution = rep(0.25, n),
    CRS = rep("PL-1992", n),
    URL = paste0("https://example.org/", seq_len(n)),
    filename = paste0("t", seq_len(n)),
    stringsAsFactors = FALSE
  )
  mods <- list(...)
  for (nm in names(mods)) base[[nm]] <- mods[[nm]]
  base
}

test_that("a clean selection passes the check", {
  expect_silent(check_mosaicable(fake_index()))
})

test_that("each kind of mixture is refused, and named", {
  expect_error(check_mosaicable(fake_index(2, year = c(2024L, 2025L))), "vintage")
  expect_error(check_mosaicable(fake_index(2, composition = c("RGB", "CIR"))),
               "band composition")
  expect_error(check_mosaicable(fake_index(2, resolution = c(0.25, 0.5))),
               "resolution")
  expect_error(check_mosaicable(fake_index(2, CRS = c("PL-1992", "PL-2000:S6"))),
               "coordinate system")
  expect_error(check_mosaicable(fake_index(2, VRS = c("PL-KRON86-NH", "PL-EVRF2007-NH"))),
               "vertical datum")
  expect_error(check_mosaicable(fake_index(2, product = factor(c("DTM", "DSM")))),
               "product")
})

test_that("several disagreements are reported together, not one per run", {
  bad <- fake_index(2, year = c(2024L, 2025L), composition = c("RGB", "CIR"))
  msg <- tryCatch(check_mosaicable(bad), error = conditionMessage)
  expect_match(msg, "vintage")
  expect_match(msg, "band composition")
})

test_that("point clouds are refused before anything else", {
  pc <- fake_index(2, product = factor(rep("PointCloud", 2)))
  expect_error(check_mosaicable(pc), "cannot be mosaicked")
})

test_that("the coordinate system is read from the index, not the files", {
  expect_equal(index_epsg(fake_index()), 2180L)
  expect_equal(index_epsg(fake_index(1, CRS = "PL-2000:S6")), 2177L)
  expect_true(is.na(index_epsg(fake_index(2, CRS = c("PL-1992", "PL-2000:S6")))))
  expect_true(is.na(index_epsg(fake_index(1, CRS = "something new"))))
  expect_equal(index_epsg(data.frame(x = 1)), 2180L)
})

test_that("a raster is recognised by its content, not its file name", {
  dir <- withr::local_tempdir()

  # the orthophoto index names its tiles with no extension at all
  tif <- file.path(dir, "83832_1514566_N-33-130-D-a-4-3")
  writeBin(as.raw(c(0x49, 0x49, 0x2a, 0x00, rep(0, 20))), tif)
  expect_true(is_raster_file(tif))

  asc <- file.path(dir, "grid_no_ext")
  writeLines(c("ncols 2", "nrows 2", "1 2", "3 4"), asc)
  expect_true(is_raster_file(asc))

  zip <- file.path(dir, "bundle.zip")
  writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04, rep(0, 20))), zip)
  expect_false(is_raster_file(zip))

  expect_false(is_raster_file(file.path(dir, "missing")))
  expect_false(is_raster_file(dir))
})

test_that("tile_mosaic validates before touching the network", {
  expect_error(tile_mosaic(fake_index()[0, ]), "non-empty index")
  expect_error(tile_mosaic("not an index"), "non-empty index")
  expect_error(tile_mosaic(fake_index(), crop = "aoi"), "needs an `aoi`")
})

test_that("a sheet appearing twice is refused, with the filled/unfilled hint", {
  dup <- fake_index(2)
  dup$sheetID <- c("N-33-130-D-a-3-2", "N-33-130-D-a-3-2")
  dup$isFilled <- c(FALSE, TRUE)

  msg <- tryCatch(check_mosaicable(dup), error = conditionMessage)
  expect_match(msg, "more than once")
  expect_match(msg, "N-33-130-D-a-3-2", fixed = TRUE)
  expect_match(msg, "isFilled", fixed = TRUE)
})

test_that("duplicate sheets with no isFilled column point at seriesID instead", {
  dup <- fake_index(2)
  dup$sheetID <- c("A", "A")
  msg <- tryCatch(check_mosaicable(dup), error = conditionMessage)
  expect_match(msg, "seriesID", fixed = TRUE)
})

test_that("distinct sheets pass", {
  ok <- fake_index(3)
  ok$sheetID <- c("A", "B", "C")
  ok$isFilled <- c(TRUE, TRUE, TRUE)
  expect_silent(check_mosaicable(ok))
})

# Joining through a VRT -------------------------------------------------------

tile_file <- function(value, xmin, crs = "EPSG:2180") {
  r <- terra::rast(nrows = 10, ncols = 10, xmin = xmin, xmax = xmin + 10,
                   ymin = 0, ymax = 10, crs = crs)
  terra::values(r) <- value
  path <- tempfile(fileext = ".tif")
  terra::writeRaster(r, path, overwrite = TRUE)
  path
}

test_that("a single tile is opened directly, not wrapped in a VRT", {
  skip_if_not_installed("terra")
  out <- join_tiles(tile_file(7, 0), epsg = 2180L)
  expect_s4_class(out, "SpatRaster")
  expect_equal(unique(terra::values(out)[, 1]), 7)
})

test_that("neighbouring tiles join into one raster covering both", {
  skip_if_not_installed("terra")
  out <- join_tiles(c(tile_file(1, 0), tile_file(2, 10)), epsg = 2180L)
  expect_equal(unname(as.vector(terra::ext(out))[1:2]), c(0, 20))
  expect_setequal(unique(terra::values(out)[, 1]), c(1, 2))
})

test_that("where tiles overlap the first one wins, as mosaic(fun = 'first') did", {
  skip_if_not_installed("terra")
  # the second tile covers x 5..15, so x 5..10 is claimed by both
  out <- join_tiles(c(tile_file(1, 0), tile_file(2, 5)), epsg = 2180L)
  overlap <- terra::crop(out, terra::ext(6, 9, 1, 9))
  expect_equal(unique(terra::values(overlap)[, 1]), 1)
})

test_that("tiles with no projection of their own take it from the index", {
  skip_if_not_installed("terra")
  # ASCII grid is the real case: GDAL's driver carries no projection at all,
  # which is why the index has to supply one.
  asc <- function(value, xmin) {
    r <- terra::rast(nrows = 10, ncols = 10, xmin = xmin, xmax = xmin + 10,
                     ymin = 0, ymax = 10)
    terra::values(r) <- value
    path <- tempfile(fileext = ".asc")
    terra::writeRaster(r, path, overwrite = TRUE)
    path
  }
  bare <- c(asc(1, 0), asc(2, 10))
  expect_true(is.na(terra::crs(terra::rast(bare[1]), describe = TRUE)$code))

  out <- join_tiles(bare, epsg = 2180L)
  expect_equal(terra::crs(out, describe = TRUE)$code, "2180")

  # and an index that could not say which system it is leaves them alone
  expect_true(is.na(terra::crs(join_tiles(bare, epsg = NA_integer_),
                               describe = TRUE)$code))
})

test_that("one sheet published in two formats is caught, and the hint says so", {
  # The elevation services publish every sheet both as a grid and as a list of
  # points. Mixing them means half the mosaic is not a raster at all.
  idx <- fake_index(2, sheetID = c("N-34-78-D", "N-34-78-D"),
                    format = c("ARC/INFO ASCII GRID", "ASCII XYZ GRID"))
  expect_error(check_mosaicable(idx), "file format")

  same_format <- fake_index(2, sheetID = c("N-34-78-D", "N-34-78-D"),
                            format = rep("ARC/INFO ASCII GRID", 2))
  expect_error(check_mosaicable(same_format), "appears")
})

test_that("tiles a virtual raster cannot bridge are refused, not left out", {
  skip_if_not_installed("terra")
  one_band <- tile_file(1, 0)
  three_band <- local({
    r <- terra::rast(nrows = 10, ncols = 10, xmin = 10, xmax = 20, ymin = 0,
                     ymax = 10, nlyrs = 3, crs = "EPSG:2180")
    terra::values(r) <- 2
    p <- tempfile(fileext = ".tif"); terra::writeRaster(r, p, overwrite = TRUE); p
  })
  expect_error(join_tiles(c(one_band, three_band), epsg = 2180L),
               "Only 1 of 2 tiles")
  expect_error(join_tiles(c(one_band, three_band), epsg = 2180L), "holes")

  # a different coordinate system is the other thing it cannot bridge
  elsewhere <- tile_file(3, 10, crs = "EPSG:2177")
  expect_error(join_tiles(c(one_band, elsewhere), epsg = 2180L), "Only 1 of 2")
})

test_that("the count of joined tiles is read from the VRT itself", {
  vrt <- tempfile(fileext = ".vrt")
  writeLines(c("<VRTDataset>", "  <SourceFilename>a.tif</SourceFilename>",
               "  <SourceFilename>b.tif</SourceFilename>", "</VRTDataset>"), vrt)
  expect_true(check_vrt_complete(vrt, 2L))
  expect_error(check_vrt_complete(vrt, 3L), "Only 2 of 3")
})

test_that("a source listed once per band counts as one tile", {
  # a three-band source appears three times; counting lines would call that
  # three tiles and let a genuinely missing one through
  vrt <- tempfile(fileext = ".vrt")
  writeLines(c("<VRTDataset>",
               rep("  <SourceFilename relativeToVRT=\"0\">a.tif</SourceFilename>", 3),
               "</VRTDataset>"), vrt)
  expect_equal(vrt_sources(vrt), "a.tif")
  expect_error(check_vrt_complete(vrt, 2L), "Only 1 of 2")
})

test_that("layers are named from the index, not from a temporary file", {
  skip_if_not_installed("terra")
  one <- terra::rast(nrows = 4, ncols = 4); terra::values(one) <- 1
  expect_equal(names(name_layers(one, data.frame(product = "DTM"))), "DTM")

  three <- c(one, one, one)
  expect_equal(names(name_layers(three, data.frame(composition = "RGB"))),
               c("R", "G", "B"))
  # false colour puts near infrared where red would be
  expect_equal(names(name_layers(three, data.frame(composition = "CIR"))),
               c("NIR", "R", "G"))
})

test_that("an index that cannot say what the bands are leaves them alone", {
  skip_if_not_installed("terra")
  one <- terra::rast(nrows = 4, ncols = 4); terra::values(one) <- 1
  names(one) <- "whatever"
  expect_equal(names(name_layers(one, data.frame(x = 1))), "whatever")

  # a mixture the index cannot resolve to one name is not guessed at
  four <- c(one, one, one, one)
  expect_equal(length(names(name_layers(four, data.frame(composition = "RGB")))), 4L)
})
