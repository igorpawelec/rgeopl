test_that("the vocabulary resolves to the register the service actually has", {
  expect_equal(gdos_layers("reserves"), c(reserves = "Rezerwaty"))
  expect_length(gdos_layers("all"), length(GDOS_LAYERS))

  # one word for both directives, because the question rarely means only one
  n2k <- gdos_layers("natura2000")
  expect_setequal(names(n2k), c("birds", "habitats"))

  # and it composes with the rest rather than replacing it
  mixed <- gdos_layers(c("natura2000", "reserves"))
  expect_setequal(names(mixed), c("birds", "habitats", "reserves"))
})

test_that("a register that does not exist is named, with what does", {
  expect_error(gdos_layers("forests"), "No register called \"forests\"")
  expect_error(gdos_layers("forests"), "reserves")
  expect_error(gdos_layers(c("reserves", "nonsense")), "\"nonsense\"")
})

test_that("the bounding box goes out easting first, with the short CRS name", {
  # The two belong together: this service reads EPSG:2180 in the order sf
  # writes it, and the urn: spelling in the opposite order. Mixing them
  # returns an empty answer rather than an error, so the pairing is the test.
  q <- gdos_query("Rezerwaty", c(xmin = 100, ymin = 200, xmax = 300, ymax = 400))
  expect_equal(q$BBOX, "100,200,300,400,EPSG:2180")
  expect_false(grepl("urn:", q$BBOX))
  expect_equal(q$SRSNAME, "EPSG:2180")
})

test_that("a query with no area asks for the whole country", {
  q <- gdos_query("ParkiNarodowe", NULL)
  expect_null(q$BBOX)
  expect_equal(q$TYPENAMES, "GDOS:ParkiNarodowe")
  expect_equal(q$OUTPUTFORMAT, "application/json")
})

test_that("counting asks for hits and nothing else", {
  q <- gdos_query("Rezerwaty", NULL, hits = TRUE)
  expect_equal(q$RESULTTYPE, "hits")
  expect_null(q$COUNT)
  expect_null(q$OUTPUTFORMAT)   # hits comes back as XML, not GeoJSON
})

test_that("columns are renamed to the same three, whatever the layer calls them", {
  skip_if_not_installed("sf")
  raw <- sf::st_sf(
    id = "x.1", gid = 7L, nazwa = "Bagno", kod = "PLH123456",
    kodinspire = "PL.ZIPOP.1393.N2K.PLH123456",
    geometry = sf::st_sfc(sf::st_point(c(600000, 500000)), crs = 2180))
  out <- standardise_gdos(raw, "habitats")

  expect_equal(names(out)[1:4], c("type", "name", "code", "inspire_id"))
  expect_equal(out$type, "habitats")
  expect_equal(out$name, "Bagno")
  expect_false(any(c("id", "gid", "nazwa", "kod") %in% names(out)))
})

test_that("a layer without a site code still has the column", {
  skip_if_not_installed("sf")
  raw <- sf::st_sf(gid = 1L, nazwa = "Ruszów", kodinspire = "PL.X.1",
                   geometry = sf::st_sfc(sf::st_point(c(1, 2)), crs = 2180))
  out <- standardise_gdos(raw, "reserves")
  expect_true("code" %in% names(out))
  expect_true(is.na(out$code))
})

test_that("registers with different columns bind without losing either", {
  skip_if_not_installed("sf")
  pt <- function(nm, extra = NULL) {
    x <- sf::st_sf(type = nm, name = "A", code = NA_character_,
                   inspire_id = "PL.1",
                   geometry = sf::st_sfc(sf::st_point(c(1, 2)), crs = 2180))
    if (!is.null(extra)) x[[extra]] <- "dąb"
    x
  }
  out <- bind_gdos(list(pt("reserves"), pt("monuments_point", "gatunek")))

  expect_equal(nrow(out), 2L)
  expect_true("gatunek" %in% names(out))
  expect_equal(out$gatunek, c(NA, "dąb"))
})

test_that("nothing protected here is an empty answer, not an error", {
  skip_if_not_installed("sf")
  e <- empty_gdos()
  expect_s3_class(e, "sf")
  expect_equal(nrow(e), 0L)
  expect_equal(names(e)[1:4], c("type", "name", "code", "inspire_id"))
  expect_equal(sf::st_crs(e)$epsg, 2180L)
})
