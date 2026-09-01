# The functions people type, against recorded answers.
#
# Everything else in this suite is offline by construction: it tests the parts
# that turn a service's answer into something usable, with the answer made up.
# That leaves the entry points untested, and the gap is not theoretical -- when
# `format` was added to `dem_request()` and every later argument shifted one
# place, nothing here noticed.
#
# So the real answers are recorded once, with httptest2, and replayed. The
# fixtures live under tests/testthat/fixtures/. They are index and metadata
# calls, not downloads: `dem_get()`, `ortho_get()` and the tile
# fetches are deliberately not recorded -- a single elevation tile is tens of
# megabytes and does not belong in a package. Nor does the national unit
# catalogue behind bdl_catalogue() and bdl_overview(): 9 MB of JSON for two
# calls, which would quadruple the package.
#
# To re-record after a service changes, delete the directory and run the tests
# once with a working connection (VPN to Poland for anything GUGiK).
#
# The fixtures are kept out of the built package. httptest2 mirrors each URL
# into a directory tree, and these services nest deeply enough that the paths
# run past the 100 bytes a tarball can portably store -- `R CMD check` says so.
# They stay in the repository, so these tests run for anyone working from the
# source tree, which is where the argument-plumbing regressions they guard
# against are made. In a built package they skip.

skip_if_not_installed("httptest2")
skip_if_not(dir.exists("fixtures"),
            "recorded answers are not shipped in the built package")
library(httptest2)

# The package caches index answers itself, which would serve the second call
# from disk and record nothing. Every test gets its own empty cache.
local_fresh_cache <- function(env = parent.frame()) {
  dir <- file.path(tempdir(), paste0("net-", as.integer(runif(1, 1, 1e9))))
  withr::local_options(list(rgeopl.cache_dir = dir), .local_envir = env)
  withr::defer(unlink(dir, recursive = TRUE), envir = env)
}

# Głęboczek for the elevation archive, which is rich there; Ramsowo for the
# forest and conservation registers, which Głęboczek has none of nearby.
gleboczek <- function(buffer = 300) as_aoi(c(16.80, 52.44), buffer = buffer)
ramsowo <- function(buffer = 800) as_aoi(c(21.05, 53.80), buffer = buffer)

with_mock_dir("fixtures/gugik", {
  test_that("dem_request() comes back standardised, whatever the service calls things", {
    local_fresh_cache()
    idx <- dem_request(gleboczek(), quiet = TRUE)

    expect_s3_class(idx, "sf")
    expect_gt(nrow(idx), 0L)
    expect_true(all(c("sheetID", "year", "product", "format", "resolution",
                      "density", "CRS", "VRS", "URL", "filename") %in% names(idx)))
    expect_equal(sf::st_crs(idx)$epsg, 2180L)

    # the two units the service reports in one text field, split apart
    expect_true(is.numeric(idx$resolution))
    expect_true(is.numeric(idx$density))
    expect_true(inherits(idx$date, "Date") || inherits(idx$date, "POSIXct"))
  })

  test_that("dem_request(format =) keeps one form of each sheet", {
    local_fresh_cache()
    grids <- dem_request(gleboczek(), format = "grid", quiet = TRUE)
    expect_setequal(unique(as.character(grids$format)), "ARC/INFO ASCII GRID")
    expect_gt(nrow(grids), 0L)
  })

  test_that("ortho_request() carries a band composition instead of a format", {
    local_fresh_cache()
    idx <- ortho_request(gleboczek(), quiet = TRUE)

    expect_s3_class(idx, "sf")
    expect_true("composition" %in% names(idx))
    expect_false("format" %in% names(idx))
    expect_true(all(idx$composition %in% c("RGB", "CIR")))
  })

  test_that("pointcloud_request() answers with clouds and nothing else", {
    local_fresh_cache()
    idx <- pointcloud_request(gleboczek(), quiet = TRUE)

    expect_s3_class(idx, "sf")
    expect_setequal(unique(as.character(idx$product)), "PointCloud")
    # the label tracks the era, but every file is .laz
    expect_true(all(tolower(tools::file_ext(idx$URL)) == "laz"))
  })

  test_that("coverage() measures a vintage against the area, not the tiles", {
    local_fresh_cache()
    idx <- dem_request(gleboczek(), format = "grid", quiet = TRUE)
    cov <- coverage(subset(idx, product == "DTM"), by = "year", aoi = gleboczek())

    expect_true(all(c("year", "tiles", "area_km2", "aoi_share") %in% names(cov)))
    expect_true(all(cov$aoi_share >= 0 & cov$aoi_share <= 1.001))
  })

  test_that("chm_years() offers only vintages holding both halves", {
    local_fresh_cache()
    yrs <- chm_years(gleboczek(), quiet = TRUE)

    expect_true(all(c("year", "resolution", "surface", "terrain") %in% names(yrs)))
    expect_true(all(yrs$surface > 0 & yrs$terrain > 0))
    expect_false(is.unsorted(rev(yrs$year)))
  })
})

with_mock_dir("fixtures/bdl", {
  test_that("the forest hierarchy comes back with the address parsed out", {
    local_fresh_cache()
    d <- bdl_directorates(ramsowo(), quiet = TRUE)
    n <- bdl_inspectorates(ramsowo(), quiet = TRUE)
    l <- bdl_ranges(ramsowo(), quiet = TRUE)

    for (x in list(d, n, l)) {
      expect_s3_class(x, "sf")
      expect_equal(sf::st_crs(x)$epsg, 2180L)
      expect_gt(nrow(x), 0L)
    }
    # a regional directorate has no forest address of its own; the levels
    # underneath it do
    expect_false("adr_for" %in% names(d))
    expect_true(all(c("adr_for", "inspectorate_name") %in% names(n)))
    expect_true(all(c("adr_for", "range_name") %in% names(l)))
  })

  test_that("subareas carry the whole stand description, not just an address", {
    local_fresh_cache()
    w <- bdl_subareas(ramsowo(3000), quiet = TRUE)

    expect_gt(nrow(w), 0L)
    expect_true(all(c("species", "species_age", "area_ha", "site_type",
                      "forest_function", "rotation_age") %in% names(w)))
    expect_true(is.numeric(w$area_ha))
  })

  test_that("compartments are dissolved from the address, not fetched", {
    local_fresh_cache()
    o <- bdl_compartments(ramsowo(3000), quiet = TRUE)
    expect_s3_class(o, "sf")
    expect_true("compartment" %in% names(o))
  })

  test_that("a forest address finds the unit it belongs to", {
    local_fresh_cache()
    u <- bdl_by_address("07-32", quiet = TRUE)
    expect_s3_class(u, "sf")
    expect_gt(nrow(u), 0L)
  })
})

with_mock_dir("fixtures/prg", {
  test_that("PRG boundaries come back for the area asked about, not another", {
    local_fresh_cache()
    b <- prg_boundaries(gleboczek(2000), level = "commune", quiet = TRUE)

    expect_s3_class(b, "sf")
    expect_equal(sf::st_crs(b)$epsg, 2180L)
    # the bounding box is read northing-first by this service; if that were
    # wrong the answer would be a different part of the country entirely
    expect_true(sf::st_intersects(sf::st_union(sf::st_geometry(b)),
                                  sf::st_union(aoi_geom(gleboczek(2000))),
                                  sparse = FALSE)[1, 1])
  })
})

with_mock_dir("fixtures/gdos", {
  test_that("protected areas come back for the area, tagged by register", {
    local_fresh_cache()
    p <- protected_areas(ramsowo(3000), type = "natura2000", quiet = TRUE)

    expect_s3_class(p, "sf")
    expect_equal(sf::st_crs(p)$epsg, 2180L)
    expect_true(all(p$type %in% c("birds", "habitats")))
    expect_true(all(c("type", "name", "code", "inspire_id") %in% names(p)))
    # this service reads the bounding box easting-first; the other spelling
    # returns an empty answer rather than an error
    expect_gt(nrow(p), 0L)
  })
})
