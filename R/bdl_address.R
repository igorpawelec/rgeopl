# Look a unit up by its forest address ---------------------------------------

#' Find a forest unit by its address
#'
#' The forest address is the natural key for anything in the State Forests, and
#' a truncated one names a whole level: `"04"` is a regional directorate,
#' `"04-02"` a forest inspectorate, `"04-02-2-11"` a forest range. Give as much of
#' it as you have and the matching level comes back.
#'
#' Padding does not matter. Both the service's own fixed-width form
#' (`"09-01-2-10-187   -f   -00"`) and the way people write it
#' (`"09-01-2-10-187-f"`) are accepted.
#'
#' @param adr A forest address, whole or truncated. See details for what each
#'   length means.
#' @param quiet Suppress progress messages.
#'
#' @details
#' The number of components decides what is returned:
#'
#' \describe{
#'   \item{`"04"`}{the regional directorate (RDLP)}
#'   \item{`"04-02"`}{the forest inspectorate (nadlesnictwo)}
#'   \item{`"04-02-2"`}{every forest range in that sub-district (obreb)}
#'   \item{`"04-02-2-11"`}{the forest range (lesnictwo)}
#'   \item{`"04-02-2-11-123"`}{every subarea in that compartment (oddzial)}
#'   \item{`"04-02-2-11-123-a"`}{the single subarea (wydzielenie)}
#' }
#'
#' Below the forest range there is no index to query directly, so the range is
#' resolved first and its subareas are then filtered locally. That keeps
#' the request bounded: a range holds hundreds of subareas, a regional
#' directorate hundreds of thousands.
#'
#' @return An `sf` data frame in EPSG:2180, as from [bdl_unit()].
#'
#' @examples
#' \dontrun{
#' bdl_by_address("04-02")            # Bircza forest inspectorate
#' bdl_by_address("04-02-2-11")       # Turnica forest range
#' bdl_by_address("04-02-2-11-123-a") # one subarea
#' }
#'
#' @seealso [bdl_unit()] to search by name instead.
#' @export
bdl_by_address <- function(adr, quiet = FALSE) {
  parts <- split_address(adr)
  depth <- address_depth(parts)
  if (depth == 0L) {
    stop("`", adr, "` does not look like a forest address.", call. = FALSE)
  }

  if (depth <= 2L) {
    collection <- if (depth == 1L) "rdlp" else "nadlesnictwa"
    return(address_lookup(collection, parts, depth, quiet))
  }
  if (depth <= 4L) {
    return(address_lookup("lesnictwa", parts, depth, quiet))
  }

  # Subarea level: resolve the range, then filter its subareas.
  range_adr <- paste(parts[c("directorate_cd", "inspectorate_cd", "obreb_cd", "range_cd")],
                     collapse = "-")
  if (!quiet) message("Resolving the forest range ", range_adr, " first...")
  rng <- address_lookup("lesnictwa", parts, 4L, quiet = TRUE)

  # Filter on the address, not on the range's outline. The address is the
  # authoritative key; subarea polygons do not always sit strictly inside
  # the range polygon, and clipping by geometry silently drops the ones that
  # straddle it -- which is how a compartment of ten comes back holding one.
  st <- bdl_subareas(rng, within_aoi = FALSE, quiet = quiet)

  # First narrow to the range by address, then within it by compartment and
  # subarea, so the error can say which compartments that range actually has.
  in_range <- address_match(st, parts,
                            c("directorate_cd", "inspectorate_cd", "obreb_cd", "range_cd"))
  if (!any(in_range)) {
    stop("No subareas are addressed to `", range_adr, "`.", call. = FALSE)
  }
  st <- st[in_range, , drop = FALSE]
  hit <- address_match(st, parts, c("compartment", "subarea", "part"))

  if (!any(hit)) {
    compartments <- sort(unique(stats::na.omit(st$compartment)))
    stop("No subarea matches `", adr, "`. Compartments in ", range_adr, ": ",
         paste(utils::head(compartments, 15), collapse = ", "),
         if (length(compartments) > 15) ", ..." else "", ".", call. = FALSE)
  }
  if (!quiet) message("  ", sum(hit), " subarea(s) match")
  new_bdl(st[hit, , drop = FALSE], "subareas")
}

# TRUE where every named component of the address agrees. Components the user
# did not give are ignored rather than treated as a wildcard failure.
address_match <- function(x, parts, fields) {
  hit <- rep(TRUE, nrow(x))
  for (f in fields) {
    if (is.na(parts[[f]])) next
    hit <- hit & !is.na(x[[f]]) & x[[f]] == parts[[f]]
  }
  hit
}

# Split a written address into its seven components. Works on both the
# service's fixed-width form and the loose one people type, because trimming
# the padded fields leaves exactly the same values.
split_address <- function(adr) {
  if (length(adr) != 1L || is.na(adr)) {
    stop("`adr` must be a single forest address.", call. = FALSE)
  }
  bits <- trimws(strsplit(trimws(as.character(adr)), "-", fixed = TRUE)[[1]])
  bits[!nzchar(bits)] <- NA_character_
  length(bits) <- 7L
  stats::setNames(bits, c("directorate_cd", "inspectorate_cd", "obreb_cd", "range_cd",
                          "compartment", "subarea", "part"))
}

# How many leading components were actually given.
address_depth <- function(parts) {
  given <- !is.na(parts)
  if (!given[1]) return(0L)
  run <- which(!given)
  if (length(run) == 0L) return(length(parts))
  unname(run[1] - 1L)
}

address_lookup <- function(collection, parts, depth, quiet) {
  if (!quiet) message("Looking up ", collection, " by address...")
  cat_ <- oapif_catalogue(BDL, collection)
  if (is.null(cat_)) stop("The name table came back empty.", call. = FALSE)

  keys <- if (collection == "rdlp") {
    data.frame(directorate_cd = cat_$region_cd, inspectorate_cd = NA_character_,
               obreb_cd = NA_character_, range_cd = NA_character_,
               stringsAsFactors = FALSE)
  } else {
    parse_forest_address(cat_$adress_forest)[,
      c("directorate_cd", "inspectorate_cd", "obreb_cd", "range_cd")]
  }

  fields <- c("directorate_cd", "inspectorate_cd", "obreb_cd", "range_cd")[seq_len(min(depth, 4L))]
  hit <- rep(TRUE, nrow(keys))
  for (f in fields) hit <- hit & !is.na(keys[[f]]) & keys[[f]] == parts[[f]]

  if (!any(hit)) {
    stop("No ", collection, " with address `",
         paste(stats::na.omit(parts[fields]), collapse = "-"), "`.",
         call. = FALSE)
  }
  if (!quiet) message("  ", sum(hit), " unit(s) match; fetching geometry")

  parts_sf <- lapply(cat_$.id[hit], function(i) oapif_item(BDL, collection, i))
  out <- add_unit_names(standardise_bdl(do.call(rbind, parts_sf)))
  new_bdl(out, paste0(collection, " by address"))
}
