# Protected areas ------------------------------------------------------------
#
# The register is GDOŚ's, not the State Forests'. BDL renders protected areas
# on its own maps, but publishes nothing about them as data -- its whole public
# service is seven layers of administrative units and subareas. So this goes to
# the body that keeps the register.
#
# It is a WFS 2.0, and two things about it had to be measured rather than
# assumed.
#
# The first is the axis order, which is the trap PRG already taught us. The
# spelling of the coordinate system in the BBOX decides it, and both spellings
# work if the order matches:
#
#   BBOX=...,EPSG:2180                    easting first   (what sf hands you)
#   BBOX=...,urn:ogc:def:crs:EPSG::2180   northing first  (what PRG uses)
#
# Mismatch them and the service answers with nothing at all -- no error, no
# warning, an empty result for an area full of reserves. The short spelling is
# used here because it takes `aoi_bbox()` unchanged.
#
# The second is that this service cannot page. STARTINDEX comes back with
# "Cannot do natural order without a primary key", so a request is one request:
# COUNT limits it, and the total from RESULTTYPE=hits says whether anything was
# left behind. That is fine at this size -- every layer fits in one call, the
# largest measured at 32 MB in 21 s -- but it means the count has to be checked
# rather than trusted.

GDOS <- "https://sdi.gdos.gov.pl/wfs"

# The layers worth naming, in the vocabulary of the register. Every one carries
# `nazwa` and `kodinspire`; the Natura 2000 pair adds `kod`, the site code.
GDOS_LAYERS <- c(
  birds = "ObszarySpecjalnejOchrony",
  habitats = "SpecjalneObszaryOchrony",
  reserves = "Rezerwaty",
  national_parks = "ParkiNarodowe",
  landscape_parks = "ParkiKrajobrazowe",
  protected_landscape = "ObszaryChronionegoKrajobrazu",
  corridors = "korytarzeEkologiczne",
  ramsar = "ramsar",
  ecological_sites = "UzytkiEkologiczne",
  landscape_complexes = "ZespolyPrzyrodniczoKrajobrazowe",
  documentation_sites = "StanowiskaDokumentacyjne",
  monuments_area = "PomnikiPrzyrodyPowierzchniowe",
  monuments_point = "PomnikiPrzyrodyPunktowe"
)

#' Protected areas covering an area of interest
#'
#' Nature conservation as the register holds it: Natura 2000 sites, reserves,
#' national and landscape parks, ecological corridors and the rest. The
#' question a stand raises the moment you have its outline -- whether anything
#' protected lies under it -- and one the Forest Data Bank cannot answer,
#' because it publishes no conservation data at all.
#'
#' @param aoi An area of interest: anything [as_aoi()] accepts. `NULL` fetches
#'   the whole country, which every one of these layers is small enough for.
#' @param type Which registers to ask. `"all"` asks every one; otherwise any of
#'   `"natura2000"` (both directives at once), `"birds"`, `"habitats"`,
#'   `"reserves"`, `"national_parks"`, `"landscape_parks"`,
#'   `"protected_landscape"`, `"corridors"`, `"ramsar"`,
#'   `"ecological_sites"`, `"landscape_complexes"`, `"documentation_sites"`,
#'   `"monuments_area"`, `"monuments_point"`. More than one may be named.
#' @param within_aoi Keep only features that actually meet the area. The
#'   service filters by bounding box alone, so for anything other than a
#'   rectangle it also returns features lying beside it.
#' @param max_features Refuse a request larger than this. The service cannot
#'   page, so this is a ceiling on one answer rather than on a walk.
#' @param quiet Suppress progress messages.
#'
#' @return An `sf` data frame in EPSG:2180 with `type` naming the register the
#'   row came from, `name`, `code` (the Natura 2000 site code, `NA` elsewhere)
#'   and `inspire_id`, followed by whatever else the layer carries.
#'
#' @section What the rows are:
#' A park and its buffer zone are separate features, both in the park layer and
#' both named after the park: `ParkiNarodowe` holds 46 rows for Poland's 23
#' national parks, half of them `... - otulina`. Summing areas without looking
#' will count the same ground twice.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#'
#' protected_areas(aoi)
#' protected_areas(aoi, "natura2000")
#'
#' # every reserve in the country, in one request
#' protected_areas(type = "reserves")
#' }
#'
#' @seealso [bdl_subareas()] for the stands themselves.
#' @export
protected_areas <- function(aoi = NULL, type = "all", within_aoi = TRUE,
                            max_features = 2e5, quiet = FALSE) {
  layers <- gdos_layers(type)
  bbox <- if (is.null(aoi)) NULL else aoi_bbox(as_aoi(aoi), crs = CRS_PL1992)

  parts <- lapply(names(layers), function(nm) {
    out <- gdos_features(layers[[nm]], bbox, max_features, nm, quiet)
    if (is.null(out) || nrow(out) == 0L) return(NULL)
    out <- standardise_gdos(out, nm)
    if (within_aoi && !is.null(aoi)) out <- keep_touching_aoi(out, as_aoi(aoi))
    if (nrow(out) == 0L) NULL else out
  })

  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0L) {
    say(quiet, "Nothing protected here.")
    return(empty_gdos())
  }
  # The layers do not all carry the same columns -- the monuments know a
  # species and a date, the reserves do not -- so binding them fills what is
  # missing rather than dropping what only one of them has.
  out <- rbind_sf(parts)
  say(quiet, "  ", nrow(out), " features across ",
      length(unique(out$type)), " register",
      if (length(unique(out$type)) == 1L) "" else "s")
  out
}

gdos_layers <- function(type) {
  type <- unique(type)
  if ("all" %in% type) return(GDOS_LAYERS)

  # one word for the pair, because "is this in Natura 2000" rarely means one
  # directive and not the other
  if ("natura2000" %in% type) {
    type <- unique(c(setdiff(type, "natura2000"), "birds", "habitats"))
  }
  unknown <- setdiff(type, names(GDOS_LAYERS))
  if (length(unknown)) {
    stop("No register called ", paste0("\"", unknown, "\"", collapse = ", "), ".",
         "\n  Available: ", paste(names(GDOS_LAYERS), collapse = ", "),
         ", natura2000, all.", call. = FALSE)
  }
  GDOS_LAYERS[type]
}

# One request per layer. The total is read first, so a refusal costs nothing
# and a short answer can be told from a complete one.
gdos_features <- function(layer, bbox, max_features, what, quiet) {
  n <- gdos_count(layer, bbox)
  if (!is.na(n) && n == 0L) return(NULL)
  if (!is.na(n) && n > max_features) {
    rlang::abort(
      c(paste0("The ", what, " register would return ", n, " features here."),
        i = paste0("The limit is ", max_features,
                   "; narrow the area, or raise `max_features` deliberately.")),
      class = "rgeopl_too_large"
    )
  }
  say(quiet, "  ", what, ": ", if (is.na(n)) "?" else n, " features")

  txt <- gp_text(GDOS, gdos_query(layer, bbox, count = max_features))
  out <- suppressWarnings(sf::st_read(txt, quiet = TRUE))
  check_complete(out, n)
}

gdos_count <- function(layer, bbox) {
  txt <- gp_text(GDOS, gdos_query(layer, bbox, hits = TRUE))
  found <- regmatches(txt, regexpr('numberMatched="[0-9]+"', txt))
  if (length(found) == 0L) return(NA_integer_)
  as.integer(gsub("[^0-9]", "", found))
}

gdos_query <- function(layer, bbox, count = NULL, hits = FALSE) {
  drop_null(list(
    SERVICE = "WFS", VERSION = "2.0.0", REQUEST = "GetFeature",
    TYPENAMES = paste0("GDOS:", layer),
    SRSNAME = paste0("EPSG:", CRS_PL1992),
    # Short spelling, easting first. See the note at the top of this file:
    # the URN spelling means the opposite order and returns nothing when mixed.
    BBOX = if (is.null(bbox)) NULL else {
      paste0(paste(round(bbox), collapse = ","), ",EPSG:", CRS_PL1992)
    },
    RESULTTYPE = if (hits) "hits" else NULL,
    COUNT = if (hits) NULL else count,
    OUTPUTFORMAT = if (hits) NULL else "application/json"
  ))
}

standardise_gdos <- function(x, type) {
  names(x)[names(x) == "nazwa"] <- "name"
  names(x)[names(x) == "kod"] <- "code"
  names(x)[names(x) == "kodinspire"] <- "inspire_id"
  if (!("code" %in% names(x))) x$code <- NA_character_

  x$type <- type
  lead <- c("type", "name", "code", "inspire_id")
  geom <- attr(x, "sf_column")
  x <- x[, c(intersect(lead, names(x)),
             setdiff(names(x), c(lead, geom, "id", "gid")), geom)]
  sf::st_transform(x, CRS_PL1992)
}

empty_gdos <- function() {
  sf::st_sf(type = character(0), name = character(0), code = character(0),
            inspire_id = character(0),
            geometry = sf::st_sfc(crs = CRS_PL1992))
}
