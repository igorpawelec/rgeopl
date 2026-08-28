# State Register of Borders (PRG) --------------------------------------------
#
# Administrative boundaries, filtered to an area of interest by the service
# itself. `rgugik` reaches these by downloading a national archive and clipping
# locally; a bounding-box query returns the three communes you asked about
# instead of the 2479 in the country.
#
# Two things about this service are worth knowing before reading the code.
#
# It speaks GML and nothing else -- `outputFormat=geojson` is refused -- so
# responses are written to a file and read with GDAL's GML driver.
#
# And it reads a bounding box **northing first**. That is the EPSG axis order
# for 2180, and the service applies it whether the CRS is given as
# `urn:ogc:def:crs:EPSG::2180` or as `EPSG:2180`. Sending the usual
# `xmin,ymin,xmax,ymax` does not fail; it silently queries somewhere else --
# measured, an area near Gniezno came back as communes around Lodz.

PRG_URL <- paste0("https://mapy.geoportal.gov.pl/wss/service/PZGIK/PRG/WFS/",
                  "AdministrativeBoundaries")

PRG_LAYERS <- c(
  country = "A00_Granice_panstwa",
  voivodeship = "A01_Granice_wojewodztw",
  county = "A02_Granice_powiatow",
  commune = "A03_Granice_gmin",
  town = "A04_Granice_miast",
  cadastral_unit = "A05_Granice_jednostek_ewidencyjnych",
  cadastral_district = "A06_Granice_obrebow_ewidencyjnych",
  inspectorate = "U06_Nadlesnictwo",
  directorate = "U07_Regionalna_dyrekcja_lasow_panstwowych"
)

PRG_PAGE <- 1000L

#' Administrative boundaries for an area
#'
#' Boundaries from the State Register of Borders, filtered to the area of
#' interest by the service rather than downloaded nationally and clipped
#' afterwards. Ask for the communes around a survey plot and three come back,
#' not two and a half thousand.
#'
#' @param aoi An area of interest: anything [as_aoi()] accepts. `NULL` returns
#'   the whole country, which for communes means 2479 polygons -- allowed, but
#'   ask for it deliberately.
#' @param level Which boundary. `"commune"`, `"county"` and `"voivodeship"` are
#'   the usual three; `"cadastral_unit"` and `"cadastral_district"` go finer,
#'   `"town"` and `"country"` sit alongside. `"inspectorate"` and
#'   `"directorate"` are the State Forests' units as the border register
#'   holds them, which is a different source from [bdl_inspectorates()] and useful
#'   precisely for that reason.
#' @param max_features Refuse to fetch more than this many.
#' @param quiet Suppress progress messages.
#'
#' @return An `sf` data frame in EPSG:2180 with `teryt` (the national unit
#'   code; a forest address prefix for the two forest levels), `name`,
#'   `level`, `area_ha` as the register records it, and the boundary.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#'
#' prg_boundaries(aoi, "commune")
#' prg_boundaries(aoi, "county")
#'
#' # every voivodeship in the country
#' prg_boundaries(level = "voivodeship")
#' }
#'
#' @export
prg_boundaries <- function(aoi = NULL, level = "commune",
                           max_features = 5000, quiet = FALSE) {
  level <- match.arg(level, names(PRG_LAYERS))
  type <- paste0("ms:", PRG_LAYERS[[level]])

  bbox_arg <- if (is.null(aoi)) NULL else prg_bbox_arg(as_aoi(aoi))

  if (!quiet) message("Querying ", PRG_LAYERS[[level]], "...")

  parts <- list()
  offset <- 0L
  repeat {
    page <- prg_page(type, bbox_arg, offset)
    if (is.null(page) || nrow(page) == 0L) break
    parts[[length(parts) + 1L]] <- page
    offset <- offset + nrow(page)
    if (nrow(page) < PRG_PAGE) break
    if (offset >= max_features) {
      rlang::warn(paste0("Stopped at ", max_features,
                         " features; raise `max_features` for more."))
      break
    }
    if (!quiet) message("  ", offset, " features so far")
  }
  if (length(parts) == 0L) {
    if (!quiet) message("  nothing here")
    return(prg_empty(level))
  }

  out <- prg_standardise(do.call(rbind, parts), level)
  if (!quiet) message("  ", nrow(out), " ", level, " boundaries")
  out
}

# The bbox argument, northing first. This is the one place where getting the
# order wrong costs nothing at request time and everything afterwards, so it
# lives in its own function with its own test.
prg_bbox_arg <- function(aoi) {
  bb <- aoi_bbox(aoi, crs = CRS_PL1992)
  paste0(
    paste(round(c(bb[["ymin"]], bb[["xmin"]], bb[["ymax"]], bb[["xmax"]])),
          collapse = ","),
    ",urn:ogc:def:crs:EPSG::2180"
  )
}

# One page. The service emits GML only, which GDAL reads from a file.
prg_page <- function(type, bbox_arg, offset) {
  params <- drop_null(list(
    service = "WFS", request = "GetFeature", version = "2.0.0",
    typeNames = type, count = PRG_PAGE, startIndex = offset,
    srsName = "urn:ogc:def:crs:EPSG::2180", bbox = bbox_arg
  ))
  txt <- gp_text(PRG_URL, params)
  if (grepl("ExceptionReport", substr(txt, 1, 500), fixed = TRUE)) {
    rlang::abort(
      c("The border register rejected the query.",
        i = trimws(gsub("\\s+", " ", substr(txt, 1, 300)))),
      class = "rgeopl_service_error"
    )
  }
  f <- tempfile(fileext = ".gml")
  on.exit(unlink(c(f, sub("\\.gml$", ".gfs", f))), add = TRUE)
  writeLines(txt, f, useBytes = TRUE)
  out <- tryCatch(suppressWarnings(sf::st_read(f, quiet = TRUE)),
                  error = function(e) NULL)
  if (is.null(out) || nrow(out) == 0L) return(NULL)
  out
}

PRG_NAMES <- c(JPT_KOD_JE = "teryt", JPT_NAZWA_ = "name",
               JPT_SJR_KO = "level_code", JPT_POWIER = "area_ha",
               IIP_IDENTY = "id")

prg_standardise <- function(x, level) {
  hit <- names(x) %in% names(PRG_NAMES)
  names(x)[hit] <- PRG_NAMES[names(x)[hit]]

  if ("area_ha" %in% names(x)) x$area_ha <- suppressWarnings(as.numeric(x$area_ha))
  x$level <- level

  keep <- c(intersect(c("teryt", "name", "level", "level_code", "area_ha", "id"),
                      names(x)),
            attr(x, "sf_column"))
  x <- x[, keep]
  if (is.na(sf::st_crs(x))) sf::st_crs(x) <- CRS_PL1992
  sf::st_transform(x, CRS_PL1992)
}

prg_empty <- function(level) {
  out <- data.frame(teryt = character(0), name = character(0),
                    level = character(0), area_ha = numeric(0),
                    stringsAsFactors = FALSE)
  out$geometry <- sf::st_sfc(crs = sf::st_crs(CRS_PL1992))
  sf::st_as_sf(out)
}
