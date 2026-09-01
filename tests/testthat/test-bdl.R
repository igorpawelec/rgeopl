test_that("the forest address is split at the right fixed positions", {
  out <- parse_forest_address("09-01-2-10-187   -f   -00")
  expect_equal(out$directorate_cd, "09")
  expect_equal(out$inspectorate_cd, "01")
  expect_equal(out$obreb_cd, "2")
  expect_equal(out$range_cd, "10")
  expect_equal(out$compartment, "187")
  expect_equal(out$subarea, "f")
  expect_equal(out$part, "00")
})

test_that("compartments carrying a letter survive the trim", {
  expect_equal(parse_forest_address("09-02-1-06-33A   -c   -00")$compartment, "33A")
})

test_that("higher administrative levels leave the lower fields NA", {
  inspectorate <- parse_forest_address("09-12- -  -      -    -")
  expect_equal(inspectorate$directorate_cd, "09")
  expect_equal(inspectorate$inspectorate_cd, "12")
  expect_true(all(is.na(unlist(inspectorate[c("obreb_cd", "range_cd", "compartment",
                                          "subarea", "part")]))))

  range <- parse_forest_address("01-01-1-02-      -    -")
  expect_equal(range$range_cd, "02")
  expect_true(is.na(range$compartment))
})

test_that("the parser is vectorised and keeps row order", {
  out <- parse_forest_address(c("09-01-2-10-187   -f   -00",
                                "09-12- -  -      -    -"))
  expect_equal(nrow(out), 2L)
  expect_equal(out$compartment, c("187", NA))
})

test_that("directorate names match their collection ids after transliteration", {
  expect_equal(normalise_name("ZIELONA GÓRA"), "zielonagora")
  expect_equal(normalise_name("Zielona_Gora"), "zielonagora")
  expect_equal(normalise_name("ŁÓDŹ"), normalise_name("Lodz"))
  expect_equal(normalise_name("BIAŁYSTOK"), normalise_name("Bialystok"))
  expect_equal(normalise_name("WROCŁAW"), normalise_name("Wroclaw"))
})

test_that("BDL column names are mapped and the address is expanded", {
  raw <- sf::st_as_sf(data.frame(
    adr_for = c("09-01-2-10-187   -f   -00", "09-01-2-10-187   -g   -00"),
    a_year = c(2026L, 2026L),
    sub_area = c(1.46, 2.0),
    species_cd = c("SO", "DB"),
    geometry = sf::st_sfc(sf::st_point(c(16.9, 52.4)),
                          sf::st_point(c(16.91, 52.41)), crs = 4326),
    stringsAsFactors = FALSE
  ))
  out <- standardise_bdl(raw)

  expect_true(all(c("directorate_cd", "inspectorate_cd", "range_cd", "compartment", "subarea",
                    "year", "area_ha", "species") %in% names(out)))
  expect_equal(out$compartment, c("187", "187"))
  expect_equal(out$subarea, c("f", "g"))
  expect_type(out$year, "integer")
  # everything comes back in the working CRS, like the GUGiK side
  expect_equal(sf::st_crs(out)$epsg, 2180L)
})

test_that("the alternative address column name is handled too", {
  raw <- sf::st_as_sf(data.frame(
    adress_forest = "09-12- -  -      -    -",
    inspectorate_name = "Koscian",
    a_year = 2026L,
    geometry = sf::st_sfc(sf::st_point(c(16.9, 52.4)), crs = 4326),
    stringsAsFactors = FALSE
  ))
  out <- standardise_bdl(raw)
  expect_true("adr_for" %in% names(out))
  expect_equal(out$inspectorate_name, "Koscian")
  expect_equal(out$inspectorate_cd, "12")
})

test_that("an empty BDL layer has the expected shape", {
  out <- empty_bdl()
  expect_s3_class(out, "sf")
  expect_equal(nrow(out), 0L)
  expect_equal(sf::st_crs(out)$epsg, 2180L)
})

test_that("printing survives losing the sf and tibble classes", {
  raw <- sf::st_as_sf(data.frame(
    adr_for = "09-01-2-10-187   -f   -00",
    a_year = 2026L,
    geometry = sf::st_sfc(sf::st_point(c(16.9, 52.4)), crs = 4326),
    stringsAsFactors = FALSE
  ))
  x <- new_bdl(standardise_bdl(raw), "subareas")
  expect_output(print(x), "BDL subareas: 1 features")
  expect_output(print(x), "current state only")
  # st_drop_geometry keeps our class but drops sf's; printing must still work
  expect_output(print(sf::st_drop_geometry(x)), "BDL")
})

test_that("name matching ignores case and Polish diacritics", {
  # built from code points so this file stays readable on a CP-1250 console
  metkow_pl <- intToUtf8(c(77, 0x119, 116, 107, 0xF3, 119))   # Metkow
  pool <- c("Metkow", metkow_pl, "Chelmek", "Bukowno")
  expect_equal(which(match_name(pool, "metkow")), c(1L, 2L))
  expect_equal(which(match_name(pool, toupper(metkow_pl))), c(1L, 2L))
  expect_equal(which(match_name(pool, "Bukowno")), 4L)
  expect_length(which(match_name(pool, "Nieistniejace")), 0L)
})

test_that("NA names never match", {
  expect_false(any(match_name(c(NA, NA_character_), "cokolwiek")))
})

test_that("unit keys come from the address where the collection lacks names", {
  ranges <- data.frame(
    adress_forest = c("02-07-1-03-      -    -", "09-01-1-02-      -    -"),
    forest_range_name = c("Metkow", "Antonin"),
    stringsAsFactors = FALSE
  )
  k <- unit_keys(ranges, "lesnictwa")
  expect_equal(k$directorate_cd, c("02", "09"))
  expect_equal(k$inspectorate_cd, c("07", "01"))
  expect_equal(k$range_name, c("Metkow", "Antonin"))
  # a forest range table carries no inspectorate name at all: matching on one
  # has to go through the codes instead
  expect_true(all(is.na(k$inspectorate_name)))
})

test_that("the directorate table keys on its own code", {
  directorates <- data.frame(region_cd = c("02", "09"),
                        region_name = c("KATOWICE", "POZNAN"),
                        stringsAsFactors = FALSE)
  k <- unit_keys(directorates, "rdlp")
  expect_equal(k$directorate_name, c("KATOWICE", "POZNAN"))
  expect_true(all(is.na(k$inspectorate_cd)))
})

test_that("bdl_unit refuses an empty request", {
  expect_error(bdl_unit(), "at least one of")
})

test_that("a missed name suggests near ones and only those", {
  keys <- data.frame(directorate_name = NA_character_, inspectorate_name = NA_character_,
                     range_name = c("Metkow", "Metna", "Bukowno"),
                     stringsAsFactors = FALSE)
  msg <- no_match_message("range", NULL, NULL, "Metkowo", keys)
  expect_match(msg, "No range called")
  expect_match(msg, "Did you mean")
  expect_true(grepl("Metkow", msg, fixed = TRUE))
  expect_false(grepl("Bukowno", msg, fixed = TRUE))
})

test_that("bdl_catalogue validates its level before touching the network", {
  expect_error(bdl_catalogue("nonsense"), "should be one of")
  expect_error(bdl_catalogue(c("inspectorate", "range")), "must be of length 1")
})

test_that("codes the service repeats are not returned twice", {
  # `nadlesnictwa` sends its own region_cd and inspectorate_cd, which the
  # forest address already carries; binding both gave inspectorate_cd.1
  raw <- sf::st_sf(
    adress_forest = "07-32- -  -      -    -  ",
    region_cd = "07", inspectorate_cd = "32", inspectorate_name = "Wipsowo",
    a_year = 2026L,
    geometry = sf::st_sfc(sf::st_point(c(600000, 700000)), crs = 2180))

  out <- standardise_bdl(raw)
  expect_false(any(grepl("[.][0-9]+$", names(out))))
  expect_equal(sum(names(out) == "inspectorate_cd"), 1L)
  expect_equal(sum(names(out) == "directorate_cd"), 1L)

  # and the one kept is the parsed address, which every level has
  expect_equal(out$directorate_cd, "07")
  expect_equal(out$inspectorate_cd, "32")
})
