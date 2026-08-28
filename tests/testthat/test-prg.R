test_that("the bbox is built northing first, as the service reads it", {
  aoi <- as_aoi(c(416481, 535097, 420167, 538072), crs = 2180)
  arg <- prg_bbox_arg(aoi)

  expect_match(arg, "^535097,416481,538072,420167,")
  expect_match(arg, "urn:ogc:def:crs:EPSG::2180$", fixed = FALSE)

  # the trap this guards: easting first would query a different part of Poland
  bits <- as.numeric(strsplit(arg, ",")[[1]][1:4])
  expect_true(bits[1] > bits[2])   # northing exceeds easting here
  expect_true(bits[3] > bits[4])
})

test_that("a point area of interest still yields a degenerate but valid box", {
  arg <- prg_bbox_arg(as_aoi(c(16.93, 52.41)))
  bits <- as.numeric(strsplit(arg, ",")[[1]][1:4])
  expect_equal(bits[1], bits[3])
  expect_equal(bits[2], bits[4])
})

test_that("every level maps to a layer the register publishes", {
  expect_true(all(c("commune", "county", "voivodeship", "country", "town",
                    "cadastral_unit", "cadastral_district",
                    "inspectorate", "directorate") %in% names(PRG_LAYERS)))
  expect_true(all(nzchar(PRG_LAYERS)))
  expect_false(any(duplicated(PRG_LAYERS)))
  # layer codes follow the register's own naming
  expect_equal(unname(PRG_LAYERS[["commune"]]), "A03_Granice_gmin")
  expect_equal(unname(PRG_LAYERS[["inspectorate"]]), "U06_Nadlesnictwo")
})

test_that("an unknown level is refused before any request", {
  expect_error(prg_boundaries(level = "parish"), "should be one of")
})

test_that("register columns are renamed and typed", {
  raw <- sf::st_as_sf(data.frame(
    JPT_KOD_JE = c("0419023", "0409033"),
    JPT_NAZWA_ = c("Gasawa", "Mogilno"),
    JPT_SJR_KO = c("GMI", "GMI"),
    JPT_POWIER = c("13581", "14200"),
    IIP_IDENTY = c("a", "b"),
    geometry = sf::st_sfc(sf::st_point(c(417000, 536000)),
                          sf::st_point(c(419000, 537000)), crs = 2180),
    stringsAsFactors = FALSE
  ))
  out <- prg_standardise(raw, "commune")

  expect_equal(names(out)[1:5], c("teryt", "name", "level", "level_code", "area_ha"))
  expect_type(out$area_ha, "double")
  expect_equal(out$area_ha, c(13581, 14200))
  expect_equal(unique(out$level), "commune")
  expect_equal(sf::st_crs(out)$epsg, 2180L)
})

test_that("an empty result has the documented shape", {
  out <- prg_empty("commune")
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0L)
  expect_equal(sf::st_crs(out)$epsg, 2180L)
  expect_true(all(c("teryt", "name", "level", "area_ha") %in% names(out)))
})
