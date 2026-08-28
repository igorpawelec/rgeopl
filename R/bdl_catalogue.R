# National listings ----------------------------------------------------------
#
# These read the attribute tables only. That is a deliberate line: the name
# tables are small and quick (measured cold: 17 directorates 0.6 s, 429
# inspectorates 1.4 s, 5259 ranges 11.3 s, and cached for a week after that),
# whereas the same collections *with* geometry are not -- the seventeen
# directorate polygons alone are 7.4 MB and take nearly two minutes, and the
# inspectorates run to 370 MB. Geometry is fetched per unit, by
# `bdl_unit()` or `bdl_by_address()`, never for the whole country by accident.

#' List every forest unit in Poland
#'
#' A flat table of the State Forests' administrative hierarchy: codes, names,
#' the forest address, and the BDL edition stamp. No geometry, so it is fast
#' enough to work with interactively.
#'
#' `year` is the edition of the BDL release, not the year a unit's management
#' plan was revised: it reads 2026 for all 429 inspectorates and for every
#' subarea sampled. It is kept because a future release could stamp
#' editions unevenly, but today it distinguishes nothing.
#'
#' @param level `"directorate"` (RDLP), `"inspectorate"` (nadlesnictwo) or `"range"`
#'   (lesnictwo). Each level carries the names of the levels above it.
#'
#' @return A data frame, one row per unit, sorted by forest address.
#'
#' @examples
#' \dontrun{
#' inspectorates <- bdl_catalogue("inspectorate")
#' nrow(inspectorates)
#' head(inspectorates)
#'
#' # how many forest ranges does each inspectorate run?
#' ranges <- bdl_catalogue("range")
#' sort(table(ranges$inspectorate_name), decreasing = TRUE)[1:10]
#'
#' # which inspectorates are split into three or more sub-districts?
#' obrebs <- tapply(ranges$obreb_cd, ranges$adr_for, function(z) length(unique(z)))
#' names(obrebs)[obrebs >= 3]
#' }
#'
#' @seealso [bdl_overview()] for the same thing summarised by directorate.
#' @export
bdl_catalogue <- function(level = c("inspectorate", "range", "directorate")) {
  level <- match.arg(level)
  directorates <- oapif_catalogue(BDL, "rdlp")

  if (level == "directorate") {
    out <- data.frame(
      directorate_cd = directorates$region_cd,
      directorate_name = directorates$region_name,
      year = as.integer(directorates$a_year),
      stringsAsFactors = FALSE
    )
    return(out[order(out$directorate_cd), , drop = FALSE])
  }

  inspectorates <- oapif_catalogue(BDL, "nadlesnictwa")
  dk <- parse_forest_address(inspectorates$adress_forest)
  d <- data.frame(
    directorate_cd = dk$directorate_cd,
    inspectorate_cd = dk$inspectorate_cd,
    inspectorate_name = inspectorates$inspectorate_name,
    year = as.integer(inspectorates$a_year),
    stringsAsFactors = FALSE
  )
  d$directorate_name <- directorates$region_name[match(d$directorate_cd, directorates$region_cd)]

  if (level == "inspectorate") {
    d$adr_for <- paste(d$directorate_cd, d$inspectorate_cd, sep = "-")
    out <- d[, c("directorate_cd", "directorate_name", "inspectorate_cd", "inspectorate_name",
                 "adr_for", "year")]
    return(out[order(out$adr_for), , drop = FALSE])
  }

  ranges <- oapif_catalogue(BDL, "lesnictwa")
  rk <- parse_forest_address(ranges$adress_forest)
  r <- data.frame(
    directorate_cd = rk$directorate_cd,
    inspectorate_cd = rk$inspectorate_cd,
    obreb_cd = rk$obreb_cd,
    range_cd = rk$range_cd,
    range_name = ranges$forest_range_name,
    year = as.integer(ranges$a_year),
    stringsAsFactors = FALSE
  )
  key <- paste(r$directorate_cd, r$inspectorate_cd)
  dkey <- paste(d$directorate_cd, d$inspectorate_cd)
  r$directorate_name <- directorates$region_name[match(r$directorate_cd, directorates$region_cd)]
  r$inspectorate_name <- d$inspectorate_name[match(key, dkey)]
  r$adr_for <- paste(r$directorate_cd, r$inspectorate_cd, r$obreb_cd, r$range_cd, sep = "-")

  out <- r[, c("directorate_cd", "directorate_name", "inspectorate_cd", "inspectorate_name",
               "obreb_cd", "range_cd", "range_name", "adr_for", "year")]
  out[order(out$adr_for), , drop = FALSE]
}

#' The State Forests at a glance
#'
#' One row per regional directorate: how many inspectorates and forest ranges it
#' runs, and the span of BDL edition stamps found among them. That span is
#' currently a single year everywhere (2026); it is reported as a range so that
#' an unevenly stamped future release would show up rather than hide.
#'
#' @return A data frame, one row per regional directorate, with a total row.
#'
#' @examples
#' \dontrun{
#' bdl_overview()
#' }
#'
#' @seealso [bdl_catalogue()] for the underlying listing.
#' @export
bdl_overview <- function() {
  d <- bdl_catalogue("inspectorate")
  r <- bdl_catalogue("range")

  by_region <- lapply(split(d, d$directorate_cd), function(x) {
    rr <- r[r$directorate_cd == x$directorate_cd[1], , drop = FALSE]
    data.frame(
      directorate_cd = x$directorate_cd[1],
      directorate_name = x$directorate_name[1],
      inspectorates = nrow(x),
      ranges = nrow(rr),
      edition_min = min(x$year, na.rm = TRUE),
      edition_max = max(x$year, na.rm = TRUE),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, by_region)
  out <- out[order(out$directorate_cd), , drop = FALSE]

  total <- data.frame(
    directorate_cd = "--", directorate_name = "POLAND",
    inspectorates = sum(out$inspectorates), ranges = sum(out$ranges),
    edition_min = min(out$edition_min), edition_max = max(out$edition_max),
    stringsAsFactors = FALSE
  )
  rbind(out, total)
}
