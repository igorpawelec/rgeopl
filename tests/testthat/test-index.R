# A synthetic index, so these tests never touch the network.
fake_raw <- function(n = 4, ortho = FALSE) {
  sq <- function(x0, y0, s = 1000) {
    sf::st_polygon(list(cbind(
      c(x0, x0 + s, x0 + s, x0, x0),
      c(y0, y0, y0 + s, y0 + s, y0)
    )))
  }
  geom <- sf::st_sfc(lapply(seq_len(n), function(i) sq(570000 + (i - 1) * 500, 151000)),
                     crs = 2180)
  base <- data.frame(
    godlo = paste0("M-33-", seq_len(n)),
    akt_rok = rep(c(2019L, 2024L), length.out = n),
    zr_danych = rep(c("Skaning laserowy", "Mapy topograficzne"), length.out = n),
    uklad_xy = "PL-1992",
    akt_data = rep(1577836800000, n), # 2020-01-01 in epoch ms
    czy_ark_wypelniony = rep(c("TAK", "NIE"), length.out = n),
    id_serie = seq_len(n),
    nazwa_pliku = paste0("tile_", seq_len(n)),
    url_do_pobrania = paste0("https://example.org/", seq_len(n), ".tif"),
    stringsAsFactors = FALSE
  )
  extra <- if (ortho) {
    data.frame(piksel = 0.25, kolor = "RGB", stringsAsFactors = FALSE)
  } else {
    data.frame(
      asortyment = rep(c("NMT", "chmura punktow"), length.out = n),
      format = rep(c("ARC/INFO ASCII GRID", "LAZ"), length.out = n),
      char_przestrz = rep(c("1.00 m", "10 p/m2"), length.out = n),
      blad_sr_wys = 0.1,
      blad_sr_syt = 0.2,
      uklad_h = rep(c("PL-KRON86-NH", "PL-EVRF2007-NH"), length.out = n),
      stringsAsFactors = FALSE
    )
  }
  sf::st_as_sf(cbind(base, extra, geometry = geom))
}

test_that("Polish field names become the rgugik-compatible ones", {
  out <- standardise_index(fake_raw())
  expect_true(all(c("sheetID", "year", "product", "format", "resolution",
                    "source", "CRS", "VRS", "avgElevErr", "avgPlanarErr",
                    "date", "isFilled", "seriesID", "filename", "URL")
                  %in% names(out)))
  expect_false(any(grepl("godlo|akt_rok|url_do_pobrania", names(out))))
})

test_that("types are converted, not left as text", {
  out <- standardise_index(fake_raw())
  expect_type(out$year, "integer")
  expect_s3_class(out$date, "Date")
  expect_equal(as.character(out$date[1]), "2020-01-01")
  expect_type(out$isFilled, "logical")
  expect_equal(out$isFilled, rep(c(TRUE, FALSE), length.out = 4))
  expect_type(out$avgElevErr, "double")
})

test_that("product and source are relabelled in English", {
  out <- standardise_index(fake_raw())
  expect_s3_class(out$product, "factor")
  expect_setequal(as.character(out$product), c("DTM", "PointCloud"))
  expect_setequal(as.character(out$source),
                  c("Laser scanning", "Topographic map"))
})

test_that("every documented source label is translated", {
  raw <- c("Skaning laserowy", "Zdj. lotnicze", "Zdj. cyfrowe",
           "Zdj. analogowe", "Scena sat.", "Mapy topograficzne")
  out <- recode_source(raw)
  expect_false(anyNA(out))
  expect_equal(unname(out), c("Laser scanning", "Aerial photo", "Digital photo",
                              "Analogue photo", "Satellite scene",
                              "Topographic map"))
})

test_that("an unrecognised source is passed through, never dropped to NA", {
  out <- recode_source(c("Skaning laserowy", "Cos zupelnie nowego"))
  expect_equal(unname(out), c("Laser scanning", "Cos zupelnie nowego"))
  expect_false(anyNA(out))
})

test_that("acquisition dates are read in UTC, not the session time zone", {
  # 2024-07-06 00:00:00 UTC, exactly as the service reports it
  ms <- 1720224000000
  withr::with_timezone("America/Los_Angeles", {
    expect_equal(as.character(as_acquisition_date(ms)), "2024-07-06")
  })
  withr::with_timezone("Europe/Warsaw", {
    expect_equal(as.character(as_acquisition_date(ms)), "2024-07-06")
  })
  withr::with_timezone("Pacific/Auckland", {
    expect_equal(as.character(as_acquisition_date(ms)), "2024-07-06")
  })
})

test_that("a date the driver already parsed is not converted twice", {
  ts <- as.POSIXct("2024-07-06 00:00:00", tz = "UTC")
  expect_equal(as.character(as_acquisition_date(ts)), "2024-07-06")
  expect_equal(as_acquisition_date(as.Date("2024-07-06")), as.Date("2024-07-06"))
})

test_that("grid spacing and point density land in separate columns", {
  out <- standardise_index(fake_raw())
  # the service reports both through one text field, in different units
  expect_equal(out$resolution, rep(c(1, NA), length.out = 4))
  expect_equal(out$density, rep(c(NA, 10), length.out = 4))
  expect_type(out$resolution, "double")
  expect_type(out$density, "double")

  # a density must never be readable as a metre value
  dtm <- out[!is.na(out$resolution), ]
  expect_true(all(as.character(dtm$product) == "DTM"))
})

test_that("a numeric pixel size is left alone and gets no density", {
  out <- standardise_index(fake_raw(ortho = TRUE))
  expect_equal(unique(out$resolution), 0.25)
  expect_true(all(is.na(out$density)))
})

test_that("the orthophoto schema is handled without a product column", {
  out <- standardise_index(fake_raw(ortho = TRUE))
  expect_equal(as.character(unique(out$product)), "Orthophoto")
  expect_true("composition" %in% names(out))
  expect_equal(out$resolution[1], 0.25)
  expect_false("VRS" %in% names(out))
})

test_that("column order is stable and geometry is kept last", {
  out <- standardise_index(fake_raw())
  expect_equal(names(out)[1:3], c("sheetID", "year", "product"))
  expect_equal(utils::tail(names(out), 1), attr(out, "sf_column"))
})

test_that("an empty result still has the right shape", {
  out <- empty_features(c("godlo", "akt_rok"), 2180)
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0L)
  expect_equal(sf::st_crs(out)$epsg, 2180L)
  expect_equal(nrow(standardise_index(out)), 0L)
})

test_that("the index prints its vintages and flags mixed datums", {
  idx <- new_index(standardise_index(fake_raw()), "elevation")
  expect_output(print(idx), "elevation index: 4 tiles")
  expect_output(print(idx), "2019, 2024")
  expect_output(print(idx), "mixed vertical datums")
})

test_that("mixing vertical datums warns, a single datum does not", {
  idx <- standardise_index(fake_raw())
  expect_warning(warn_mixed_vrs(idx), "mixes vertical reference systems")
  expect_silent(warn_mixed_vrs(idx[idx$VRS == "PL-KRON86-NH", ]))
  # an orthophoto index has no VRS column at all
  expect_silent(warn_mixed_vrs(standardise_index(fake_raw(ortho = TRUE))))
})

test_that("tile_download refuses input it cannot use", {
  idx <- standardise_index(fake_raw())
  expect_error(tile_download(idx[, c("sheetID", "year")]), "no `URL` column")
  expect_error(tile_download(idx[0, ]), "no rows")
})

test_that("object id lists are chunked to the page size", {
  expect_length(chunk(1:2500, 1000), 3L)
  expect_equal(lengths(chunk(1:2500, 1000)), c(`1` = 1000L, `2` = 1000L, `3` = 500L))
  expect_length(chunk(integer(0), 1000), 0L)
})

test_that("the ArcGIS envelope is built in the requested CRS", {
  env <- arcgis_envelope(c(xmin = 1, ymin = 2, xmax = 3, ymax = 4), 2180)
  expect_match(env, "'xmin':1.0000")
  expect_match(env, "'wkid':2180")

  spatial <- arcgis_spatial_params(as_aoi(c(571248, 151377), buffer = 500))
  expect_equal(spatial$geometryType, "esriGeometryEnvelope")
  expect_equal(spatial$inSR, "2180")
})

test_that("a short assembly warns instead of passing as complete", {
  idx <- fake_raw()
  expect_warning(check_complete(idx, 10), "assembled 4")
  expect_silent(check_complete(idx, 4))
})
