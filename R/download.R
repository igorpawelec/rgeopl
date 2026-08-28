#' Download the tiles an index points to
#'
#' Takes an index (or any filtered subset of one -- a `dplyr` pipeline is fine,
#' the class does not have to survive) and fetches every row. Files land in the
#' cache, so a tile already on disk is not fetched twice, across sessions.
#'
#' @param index An index from [dem_request()], [ortho_request()] or
#'   [pointcloud_request()], or any data frame carrying `URL` and `filename`
#'   columns.
#' @param outdir Optional directory to copy the usable files into. The cache
#'   remains the store; this is an export, not a move.
#' @param unzip Extract downloaded archives. The archive itself stays in the
#'   cache, so the cache record stays valid.
#' @param overwrite Re-download even when the file is already cached.
#' @param max_active How many downloads to have in flight at once. Defaults
#'   to `getOption("rgeopl.max_active", 6)`. Downloads are limited by
#'   throughput rather than latency, so the gain is modest -- measured at
#'   1.6x going from one connection to six -- and these are public services,
#'   so the cap is deliberate.
#' @param quiet Suppress per-file messages.
#'
#' @return The input with two columns added: `path` (the cached file, `NA`
#'   if that one failed) and `extracted` (the directory an archive was
#'   unpacked into, or `NA`). One tile failing does not abandon the rest.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("test_lasow.shp"), quiet = TRUE), buffer = 500)
#' idx <- dem_request(aoi)
#' got <- tile_download(subset(idx, year == max(year) & format == "LAZ"))
#' got$path
#' }
#'
#' @export
tile_download <- function(index, outdir = NULL, unzip = TRUE,
                          overwrite = FALSE, max_active = NULL,
                          quiet = FALSE) {
  for (v in c("URL", "filename")) {
    if (!(v %in% names(index))) {
      stop("`index` has no `", v, "` column. It should come from one of the ",
           "*_request() functions.", call. = FALSE)
    }
  }
  if (nrow(index) == 0L) {
    stop("`index` has no rows: nothing to download.", call. = FALSE)
  }

  warn_mixed_vrs(index)

  if (!is.null(outdir) && !dir.exists(outdir)) {
    dir.create(outdir, recursive = TRUE, showWarnings = FALSE)
  }

  n <- nrow(index)
  extracted <- rep(NA_character_, n)

  groups <- vapply(seq_len(n), function(i) download_group(index, i), character(1))
  labels <- vapply(seq_len(n), function(i) {
    paste(groups[i], if ("year" %in% names(index)) index$year[i] else "")
  }, character(1))

  # Fetched concurrently, grouped by product so the cache stays tidy. What the
  # network does in parallel, the bookkeeping still does in order.
  paths <- rep(NA_character_, n)
  for (g in unique(groups)) {
    i <- which(groups == g)
    paths[i] <- gp_download_many(
      index$URL[i], group = g, filenames = as.list(index$filename[i]),
      labels = labels[i], overwrite = overwrite, n_active = max_active,
      quiet = quiet
    )
  }

  missing <- is.na(paths)
  if (any(missing)) {
    rlang::warn(paste0(sum(missing), " of ", n,
                       " tiles did not download; their `path` is NA."))
  }

  for (i in which(!missing)) {
    if (unzip && grepl("\\.zip$", paths[i], ignore.case = TRUE)) {
      extracted[i] <- unzip_cached(paths[i], quiet = quiet)
    }
    if (!is.null(outdir)) export_to(paths[i], extracted[i], outdir)
  }

  index$path <- paths
  index$extracted <- extracted
  index
}

download_group <- function(index, i) {
  p <- if ("product" %in% names(index)) as.character(index$product[i]) else "other"
  if (is.na(p)) p <- "other"
  tolower(p)
}

# Extract beside the archive and keep the archive: deleting it would invalidate
# the cache record and cause a re-download on the next call.
unzip_cached <- function(archive, quiet = FALSE) {
  target <- file.path(dirname(archive),
                      sub("\\.zip$", "", basename(archive), ignore.case = TRUE))
  if (!dir.exists(target)) {
    dir.create(target, recursive = TRUE, showWarnings = FALSE)
    utils::unzip(archive, exdir = target)
    if (!quiet) message("  extracted to ", basename(target), "/")
  } else if (!quiet) {
    message("  already extracted")
  }
  target
}

export_to <- function(path, extracted, outdir) {
  if (!is.na(extracted)) {
    files <- list.files(extracted, full.names = TRUE, recursive = TRUE)
    file.copy(files, outdir, overwrite = TRUE)
  } else {
    file.copy(path, outdir, overwrite = TRUE)
  }
  invisible(TRUE)
}

# Heights from PL-KRON86-NH and PL-EVRF2007-NH are not interchangeable. Both
# appear within a few kilometres of each other, so a selection spanning
# vintages can silently span datums too.
warn_mixed_vrs <- function(index) {
  if (!("VRS" %in% names(index))) return(invisible(index))
  vrs <- unique(stats::na.omit(index$VRS))
  if (length(vrs) > 1L) {
    rlang::warn(c(
      paste0("This selection mixes vertical reference systems: ",
             paste(sort(vrs), collapse = ", "), "."),
      i = "Heights are not directly comparable between them; mosaicking across them shifts elevations.",
      i = "Filter on VRS first if the result is to be a single surface."
    ))
  }
  invisible(index)
}
