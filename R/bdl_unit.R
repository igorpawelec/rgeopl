# Look a forest unit up by name ---------------------------------------------
#
# The obvious route -- ask the service to filter on a property -- does not
# work: the OGC API accepts `forest_range_name=...` and returns zero features
# regardless. What does work is fetching the name table without geometry
# (cheap: three columns for 5259 forest ranges, cached for a week), matching
# locally, then pulling only the matched features by id.

#' Find a forest unit by name
#'
#' Turns "Metkow forest range, Chrzanow inspectorate" into a geometry you can hand
#' straight to any of the request functions. Matching ignores case and Polish
#' diacritics, so `"Metkow"` and `"Mętków"` both work.
#'
#' The most specific level you name is the one returned: give `range` and you
#' get a forest range, give only `inspectorate` and you get the whole inspectorate.
#' The coarser arguments narrow the search rather than changing the result, so
#' pass them when a name is not unique.
#'
#' @param directorate Regional directorate (RDLP) name, for example `"Katowice"`.
#' @param inspectorate Forest inspectorate (nadlesnictwo) name, for example
#'   `"Chrzanow"`.
#' @param range Forest range (lesnictwo) name, for example `"Metkow"`.
#' @param quiet Suppress progress messages.
#'
#' @return An `sf` data frame in EPSG:2180 with the matched unit or units, the
#'   forest address split into columns, and the names of the levels above it.
#'   Pass it to [as_aoi()], or to any `*_request()` function directly.
#'
#' @examples
#' \dontrun{
#' metkow <- bdl_unit(inspectorate = "Chrzanow", range = "Metkow")
#' metkow
#'
#' # what imagery exists over it?
#' ortho_request(metkow)
#'
#' # a whole inspectorate
#' bdl_unit(inspectorate = "Chrzanow")
#' }
#'
#' @export
bdl_unit <- function(directorate = NULL, inspectorate = NULL, range = NULL,
                     quiet = FALSE) {
  if (is.null(directorate) && is.null(inspectorate) && is.null(range)) {
    stop("Name at least one of `directorate`, `inspectorate` or `range`.", call. = FALSE)
  }

  level <- if (!is.null(range)) "range" else if (!is.null(inspectorate)) "inspectorate" else "directorate"
  collection <- switch(level, range = "lesnictwa", inspectorate = "nadlesnictwa",
                       directorate = "rdlp")

  if (!quiet) message("Looking up the ", level, " name table...")
  cat_ <- oapif_catalogue(BDL, collection)
  if (is.null(cat_)) stop("The name table came back empty.", call. = FALSE)

  keys <- unit_keys(cat_, collection)
  hit <- rep(TRUE, nrow(cat_))

  # Each collection names only its own level. Anything above it is identified
  # by the codes carried in the forest address, so a name given for a coarser
  # level has to be resolved to a code first.
  if (!is.null(directorate)) hit <- hit & match_directorate(keys, directorate)
  if (!is.null(inspectorate)) hit <- hit & match_inspectorate(keys, inspectorate)
  if (!is.null(range)) hit <- hit & match_name(keys$range_name, range)

  n <- sum(hit)
  if (n == 0L) {
    stop(no_match_message(level, directorate, inspectorate, range, keys), call. = FALSE)
  }
  if (n > 1L && !quiet) {
    message("  ", n, " units match; returning all of them")
  }

  ids <- cat_$.id[hit]
  if (!quiet) message("  fetching ", n, " geometr", if (n == 1L) "y" else "ies")
  parts <- lapply(ids, function(i) oapif_item(BDL, collection, i))
  out <- standardise_bdl(do.call(rbind, parts))
  out <- add_unit_names(out)
  new_bdl(out, paste0(level, " lookup"))
}

# The three collections describe their position differently: the directorates
# carry a plain code, the other two a forest address.
unit_keys <- function(cat_, collection) {
  if (collection == "rdlp") {
    return(data.frame(
      directorate_cd = cat_$region_cd,
      inspectorate_cd = NA_character_,
      directorate_name = cat_$region_name,
      inspectorate_name = NA_character_,
      range_name = NA_character_,
      stringsAsFactors = FALSE
    ))
  }
  parsed <- parse_forest_address(cat_$adress_forest)
  data.frame(
    directorate_cd = parsed$directorate_cd,
    inspectorate_cd = parsed$inspectorate_cd,
    directorate_name = NA_character_,
    inspectorate_name = if ("inspectorate_name" %in% names(cat_)) {
      cat_$inspectorate_name
    } else NA_character_,
    range_name = if ("forest_range_name" %in% names(cat_)) {
      cat_$forest_range_name
    } else NA_character_,
    stringsAsFactors = FALSE
  )
}

# A inspectorate can be named directly (in its own collection) or reached through
# the directorate and inspectorate codes in a forest range's address.
match_inspectorate <- function(keys, inspectorate) {
  if (!all(is.na(keys$inspectorate_name))) {
    return(match_name(keys$inspectorate_name, inspectorate))
  }
  inspectorates <- oapif_catalogue(BDL, "nadlesnictwa")
  found <- match_name(inspectorates$inspectorate_name, inspectorate)
  if (!any(found)) {
    stop("No forest inspectorate called `", inspectorate, "`.", call. = FALSE)
  }
  dk <- parse_forest_address(inspectorates$adress_forest[found])
  paste(keys$directorate_cd, keys$inspectorate_cd) %in%
    paste(dk$directorate_cd, dk$inspectorate_cd)
}

# A directorate can be named directly, or reached through the code carried in
# every forest address below it.
match_directorate <- function(keys, directorate) {
  if (!all(is.na(keys$directorate_name))) return(match_name(keys$directorate_name, directorate))
  directorates <- oapif_catalogue(BDL, "rdlp")
  cd <- directorates$region_cd[match_name(directorates$region_name, directorate)]
  if (length(cd) == 0L) {
    stop("No regional directorate called `", directorate, "`.", call. = FALSE)
  }
  keys$directorate_cd %in% cd
}

match_name <- function(haystack, needle) {
  !is.na(haystack) & normalise_name(haystack) == normalise_name(needle)
}

no_match_message <- function(level, directorate, inspectorate, range, keys) {
  wanted <- switch(level, range = range, inspectorate = inspectorate, directorate = directorate)
  pool <- switch(level, range = keys$range_name, inspectorate = keys$inspectorate_name,
                 directorate = keys$directorate_name)
  pool <- sort(unique(stats::na.omit(pool)))
  near <- pool[startsWith(normalise_name(pool),
                          substr(normalise_name(wanted), 1, 3))]
  msg <- paste0("No ", level, " called `", wanted, "`.")
  if (length(near)) {
    msg <- paste0(msg, " Did you mean: ",
                  paste(utils::head(near, 6), collapse = ", "), "?")
  }
  msg
}
