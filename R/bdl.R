# Forest Data Bank (BDL) client ---------------------------------------------

BDL <- "https://ogcapi.bdl.lasy.gov.pl"

#' Forest administrative units and subareas
#'
#' The Forest Data Bank publishes the State Forests' administrative hierarchy
#' and its subareas. Subareas are split across seventeen separate
#' collections, one per regional directorate; these functions hide that. The
#' directorates covering the area are looked up first (attributes only, so it
#' costs a fraction of a second) and only the relevant collections are queried.
#'
#' @param aoi An area of interest: anything [as_aoi()] accepts. Optional for
#'   the administrative levels, required for subareas, which are far too
#'   numerous to fetch blind.
#' @param within_aoi Keep only features that actually meet the area. The
#'   service filters by bounding box alone, so for anything other than a
#'   rectangle it also returns features lying beside the area. Features that
#'   straddle the boundary are kept whole, not clipped, so their recorded
#'   areas stay true.
#' @param max_features Refuse to fetch more than this many features. Raise it
#'   deliberately rather than by accident.
#' @param quiet Suppress progress messages.
#'
#' @return An `sf` data frame in EPSG:2180 with the forest address parsed into
#'   columns (see [parse_forest_address()]), `year` (the management plan
#'   vintage the unit is on) and the names of whichever administrative levels
#'   the collection carries.
#'
#' @section Address or geometry:
#' `within_aoi` filters by geometry, which is what "subareas in this area"
#' means. It is not the same as "subareas of this unit": a forest range's
#' outline overlaps subareas belonging to its neighbours. Measured on the
#' Turnica range, 04-02-2-11: 144 subareas carry its address, totalling
#' 1187 ha, while 194 subareas fall inside its polygon, totalling 1615 ha
#' -- 50 of them addressed to four other ranges. When you mean the unit rather
#' than the area, go through [bdl_by_address()], which filters on the address.
#'
#' @section No archive:
#' These services publish the **current state only**, and there is no vintage
#' to filter on either: `year` (`a_year` upstream) is the edition stamp of the
#' BDL release, identical across the whole country -- measured 2026 for all 429
#' forest inspectorates and for every subarea sampled. It does not say when a
#' unit's management plan was revised. A time series has to be built from your
#' own snapshots. This is the one respect in which BDL is poorer than the GUGiK
#' indexes, where every vintage stays available and is queryable.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#'
#' bdl_directorates(aoi)     # regional directorate (RDLP)
#' bdl_inspectorates(aoi)   # forest inspectorate (nadlesnictwo)
#' bdl_ranges(aoi)      # forest range (lesnictwo)
#'
#' st <- bdl_subareas(aoi)          # subareas (wydzielenia)
#' bl <- bdl_compartments(aoi)          # compartments (oddzialy), dissolved from the address
#'
#' # everything in one forest range
#' subset(st, range_cd == "06")
#' }
#'
#' @export
bdl_directorates <- function(aoi = NULL, within_aoi = TRUE, quiet = FALSE) {
  bdl_layer("rdlp", aoi, what = "regional directorates", within_aoi = within_aoi, quiet = quiet)
}

#' @rdname bdl_directorates
#' @export
bdl_inspectorates <- function(aoi = NULL, within_aoi = TRUE, quiet = FALSE) {
  bdl_layer("nadlesnictwa", aoi, what = "forest inspectorates", within_aoi = within_aoi, quiet = quiet)
}

#' @rdname bdl_directorates
#' @export
bdl_ranges <- function(aoi = NULL, within_aoi = TRUE, quiet = FALSE) {
  bdl_layer("lesnictwa", aoi, what = "forest ranges", within_aoi = within_aoi, quiet = quiet)
}

bdl_layer <- function(collection, aoi, what, within_aoi = TRUE, quiet = FALSE) {
  bbox <- if (is.null(aoi)) NULL else aoi_bbox(as_aoi(aoi), crs = CRS_WGS84)
  if (!quiet) message("Querying ", what, "...")
  raw <- oapif_items(BDL, collection, bbox, quiet = quiet)
  if (is.null(raw)) return(new_bdl(empty_bdl(), what))
  out <- standardise_bdl(raw)
  if (within_aoi && !is.null(aoi)) out <- keep_touching_aoi(out, as_aoi(aoi))
  new_bdl(out, what)
}

#' @rdname bdl_directorates
#' @export
bdl_subareas <- function(aoi, within_aoi = TRUE, max_features = 2e5,
                       quiet = FALSE) {
  aoi <- as_aoi(aoi)
  bbox <- aoi_bbox(aoi, crs = CRS_WGS84)

  colls <- bdl_directorate_collections(aoi, quiet = quiet)
  if (length(colls) == 0L) {
    if (!quiet) message("  no State Forests land in this area")
    return(new_bdl(empty_bdl(), "subareas"))
  }

  parts <- lapply(colls, function(cc) {
    oapif_items(BDL, cc, bbox, max_features = max_features, quiet = quiet)
  })
  parts <- parts[!vapply(parts, is.null, logical(1))]
  if (length(parts) == 0L) return(new_bdl(empty_bdl(), "subareas"))

  out <- standardise_bdl(do.call(rbind, parts))
  out <- add_unit_names(out)
  if (within_aoi) {
    n_before <- nrow(out)
    out <- keep_touching_aoi(out, aoi)
    if (!quiet && nrow(out) < n_before) {
      message("  dropped ", n_before - nrow(out),
              " subareas that met the bounding box but not the area")
    }
  }
  if (!quiet) {
    message("  ", nrow(out), " subareas, plan vintages ",
            paste(range(out$year, na.rm = TRUE), collapse = "-"))
  }
  new_bdl(out, "subareas")
}

# The subarea collections carry codes but no names, so a result reads
# "09-14" where the user wants "Lopuchowko". The name tables are small and
# change rarely, so they are fetched whole and cached for a week.
bdl_unit_names <- function() {
  directorates <- oapif_properties(BDL, "rdlp", limit = 100L)
  inspectorates <- oapif_properties(BDL, "nadlesnictwa", limit = 1000L)
  ranges <- oapif_properties(BDL, "lesnictwa", limit = 10000L)

  d_key <- parse_forest_address(inspectorates$adress_forest)
  r_key <- parse_forest_address(ranges$adress_forest)

  list(
    directorates = data.frame(
      directorate_cd = directorates$region_cd,
      directorate_name = directorates$region_name,
      stringsAsFactors = FALSE
    ),
    inspectorates = data.frame(
      directorate_cd = d_key$directorate_cd, inspectorate_cd = d_key$inspectorate_cd,
      inspectorate_name = inspectorates$inspectorate_name,
      stringsAsFactors = FALSE
    ),
    ranges = data.frame(
      directorate_cd = r_key$directorate_cd, inspectorate_cd = r_key$inspectorate_cd,
      obreb_cd = r_key$obreb_cd, range_cd = r_key$range_cd,
      range_name = ranges$forest_range_name,
      stringsAsFactors = FALSE
    )
  )
}

add_unit_names <- function(x) {
  if (!("directorate_cd" %in% names(x))) return(x)
  nm <- tryCatch(bdl_unit_names(), error = function(e) NULL)
  if (is.null(nm)) return(x)

  join <- function(x, tbl, keys) {
    key_x <- do.call(paste, c(lapply(keys, function(k) x[[k]]), sep = "|"))
    key_t <- do.call(paste, c(lapply(keys, function(k) tbl[[k]]), sep = "|"))
    tbl[[setdiff(names(tbl), keys)]][match(key_x, key_t)]
  }

  x$directorate_name <- join(x, nm$directorates, "directorate_cd")
  x$inspectorate_name <- join(x, nm$inspectorates, c("directorate_cd", "inspectorate_cd"))
  x$range_name <- join(x, nm$ranges,
                       c("directorate_cd", "inspectorate_cd", "obreb_cd", "range_cd"))

  lead <- c("directorate_cd", "directorate_name", "inspectorate_cd", "inspectorate_name",
            "obreb_cd", "range_cd", "range_name")
  keep <- c(intersect(lead, names(x)),
            setdiff(names(x), c(lead, attr(x, "sf_column"))),
            attr(x, "sf_column"))
  x[, keep]
}

#' @rdname bdl_directorates
#' @export
bdl_compartments <- function(aoi, within_aoi = TRUE, max_features = 2e5,
                       quiet = FALSE) {
  subareas <- bdl_subareas(aoi, within_aoi = within_aoi,
                       max_features = max_features, quiet = quiet)
  if (nrow(subareas) == 0L) return(new_bdl(empty_bdl(), "compartments"))

  # Compartments are not published as vectors; they are the subareas of a compartment
  # merged together, which is also self-consistent by construction.
  keys <- c("directorate_cd", "inspectorate_cd", "obreb_cd", "range_cd", "compartment")
  id <- do.call(paste, c(lapply(keys, function(k) subareas[[k]]), sep = "-"))

  if (!quiet) message("Dissolving ", nrow(subareas), " subareas into compartments...")
  idx <- split(seq_len(nrow(subareas)), id)
  geoms <- lapply(idx, function(i) sf::st_union(sf::st_geometry(subareas)[i]))

  carry <- intersect(c(keys, "directorate_name", "inspectorate_name", "range_name", "year"),
                     names(subareas))
  out <- subareas[vapply(idx, function(i) i[1], integer(1)), carry]
  sf::st_geometry(out) <- sf::st_sfc(unlist(geoms, recursive = FALSE),
                                     crs = sf::st_crs(subareas))
  out$subareas <- lengths(idx)
  # Two different areas, deliberately kept apart: the one the management plan
  # records, and the one the polygons actually enclose. They differ by around
  # a percent, and conflating them would hide that.
  out$area_ha <- if ("area_ha" %in% names(subareas)) {
    round(vapply(idx, function(i) sum(subareas$area_ha[i], na.rm = TRUE), numeric(1)), 2)
  } else {
    NA_real_
  }
  out$area_geom_ha <- round(as.numeric(sf::st_area(out)) / 1e4, 2)

  if (!quiet) message("  ", nrow(out), " compartments")
  new_bdl(out, "compartments")
}

# Which subarea collections cover this area? Attributes only: the
# directorate polygons are large and we only need their codes.
bdl_directorate_collections <- function(aoi, quiet = FALSE) {
  bbox <- aoi_bbox(as_aoi(aoi), crs = CRS_WGS84)
  props <- oapif_properties(BDL, "rdlp", bbox)
  if (is.null(props)) return(character(0))

  available <- grep("_wydzielenia$", oapif_collections(BDL), value = TRUE)
  keys <- normalise_name(sub("_wydzielenia$", "", sub("^RDLP_", "", available)))

  hit <- match(normalise_name(props$region_name), keys)
  if (anyNA(hit)) {
    rlang::warn(paste0(
      "No subarea collection found for: ",
      paste(props$region_name[is.na(hit)], collapse = ", "), "."
    ))
  }
  out <- available[stats::na.omit(hit)]
  if (!quiet && length(out) > 1L) {
    message("  area spans ", length(out), " regional directorates")
  }
  out
}

# Collection ids are transliterated directorate names; match on a form that
# survives both the diacritics and the underscores.
normalise_name <- function(x) {
  # L-with-stroke is built from its code point rather than typed: this file
  # must stay ASCII for R CMD check, and a literal Polish character here
  # would also misbehave on a CP-1250 console. iconv handles the rest, but
  # not this one, because the stroke is not an accent it can drop.
  x <- gsub(intToUtf8(0x141), "L", x)
  x <- gsub(intToUtf8(0x142), "l", x)
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- gsub("[^A-Za-z0-9]", "", x)
  tolower(x)
}

# Column mapping -------------------------------------------------------------

BDL_NAMES <- c(
  adr_for = "adr_for",
  adress_forest = "adr_for",
  a_year = "year",
  region_name = "directorate_name",
  region_cd = "directorate_cd",
  inspectorate_name = "inspectorate_name",
  inspectorate_cd = "inspectorate_cd",
  forest_range_name = "range_name",
  sub_area = "area_ha",
  nazwa = "dataset",
  area_type = "area_type",
  species_cd = "species",
  spec_age = "species_age",
  site_type = "site_type",
  forest_fun = "forest_function",
  rotat_age = "rotation_age",
  prot_categ = "protection",
  silvicult = "silviculture",
  stand_stru = "stand_structure"
)

standardise_bdl <- function(x) {
  hit <- names(x) %in% names(BDL_NAMES)
  names(x)[hit] <- BDL_NAMES[names(x)[hit]]

  if ("year" %in% names(x)) x$year <- as.integer(x$year)
  if ("adr_for" %in% names(x)) {
    x <- cbind(parse_forest_address(x$adr_for), x)
    x <- sf::st_as_sf(x)
  }

  lead <- c("directorate_cd", "directorate_name", "inspectorate_cd", "inspectorate_name",
            "obreb_cd", "range_cd", "range_name", "compartment", "subarea", "part",
            "adr_for", "year", "area_ha")
  keep <- c(intersect(lead, names(x)),
            setdiff(names(x), c(lead, attr(x, "sf_column"))),
            attr(x, "sf_column"))
  x <- x[, keep]
  sf::st_transform(x, CRS_PL1992)
}

empty_bdl <- function() {
  out <- data.frame(adr_for = character(0), year = integer(0),
                    stringsAsFactors = FALSE)
  out$geometry <- sf::st_sfc(crs = sf::st_crs(CRS_PL1992))
  sf::st_as_sf(out)
}

new_bdl <- function(x, what) {
  attr(x, "rgeopl_what") <- what
  class(x) <- unique(c("rgeopl_bdl", class(x)))
  x
}

#' @export
print.rgeopl_bdl <- function(x, ...) {
  what <- attr(x, "rgeopl_what") %||% "layer"
  cat("<rgeopl BDL ", what, ": ", nrow(x), " features>\n", sep = "")
  if (nrow(x) > 0L) {
    if ("inspectorate_name" %in% names(x)) {
      d <- sort(unique(stats::na.omit(x$inspectorate_name)))
      if (length(d)) {
        cat("  inspectorates: ", paste(utils::head(d, 6), collapse = ", "),
            if (length(d) > 6) paste0(", ... (", length(d), ")") else "",
            "\n", sep = "")
      }
    }
    if ("year" %in% names(x)) {
      yrs <- sort(unique(stats::na.omit(x$year)))
      cat("  plan vintages: ", paste(yrs, collapse = ", "),
          "  (current state only, not an archive)\n", sep = "")
    }
  }
  print_without_class(x, "rgeopl_bdl", ...)
  invisible(x)
}

# Forest address -------------------------------------------------------------

#' Split a forest address into its parts
#'
#' The State Forests address (*adres lesny*) is a fixed-width string, 25
#' characters, seven dash-separated fields: regional directorate, forest
#' inspectorate, sub-district, forest range, compartment, subarea and part. Higher
#' administrative levels leave the lower fields blank rather than omitting
#' them, so the positions are the same everywhere and can be read directly.
#'
#' @param x Character vector of forest addresses, for example
#'   `"09-01-2-10-187   -f   -00"`.
#'
#' @return A data frame with columns `directorate_cd`, `inspectorate_cd`, `obreb_cd`,
#'   `range_cd`, `compartment`, `subarea` and `part`. Blank fields become `NA`, so a
#'   forest inspectorate's address gives an inspectorate code and nothing below it.
#'
#' @examples
#' parse_forest_address(c("09-01-2-10-187   -f   -00",
#'                        "09-02-1-06-33A   -c   -00",
#'                        "09-12- -  -      -    -"))
#'
#' @export
parse_forest_address <- function(x) {
  x <- as.character(x)
  field <- function(from, to) {
    out <- trimws(substr(x, from, to))
    out[!nzchar(out)] <- NA_character_
    out
  }
  data.frame(
    directorate_cd = field(1, 2),
    inspectorate_cd = field(4, 5),
    obreb_cd = field(7, 7),
    range_cd = field(9, 10),
    compartment = field(12, 17),
    subarea = field(19, 22),
    part = field(24, 25),
    stringsAsFactors = FALSE
  )
}
