# Mosaicking downloaded tiles ------------------------------------------------
#
# The join is the easy part. The hard part is refusing to make one where it
# would be wrong, and the wrong cases all look fine until someone reads the
# result: two orthophoto vintages joined at a flight line, an RGB tile beside a
# false-colour one, a terrain model spanning the 2019 change of vertical datum.
# None of those fail. They produce a raster that is simply not what it claims.
# So this refuses by default and takes `allow_mixed = TRUE` for a decision made
# on purpose.

# What the index calls a coordinate system, and what that is in EPSG terms.
# Index tiles in ASCII grid carry no projection of their own, so it has to come
# from here.
INDEX_CRS <- c(
  "PL-1992" = 2180L,
  "PL-2000:S5" = 2176L, "PL-2000:S6" = 2177L,
  "PL-2000:S7" = 2178L, "PL-2000:S8" = 2179L
)

#' Join downloaded tiles into one raster
#'
#' Takes an index, downloads what it points at, and mosaics it. The pair to
#' [tile_download()]: that one fetches, this one joins.
#'
#' @param index An index from [ortho_request()], [dem_request()] or
#'   [pointcloud_request()], filtered to what you want. It must describe one
#'   product, from one survey, in one coordinate system -- see below.
#' @param aoi The area to cut to. Defaults to the index's own extent when
#'   `crop = "tiles"`.
#' @param crop `"aoi"` cuts the mosaic to the area of interest, `"tiles"` keeps
#'   the full extent of every tile that was fetched.
#' @param mask Also mask to the area's outline, not just its bounding box.
#'   Only meaningful with `crop = "aoi"` and a non-rectangular area.
#' @param filename Write the result here. `NULL` keeps it in memory or in
#'   terra's temporary space, which is fine for a few tiles and not for fifty.
#' @param allow_mixed Join tiles that disagree on vintage, product, band
#'   composition, resolution or datum. Off by default, and worth leaving off:
#'   every one of those produces a raster that looks finished and is not.
#' @param overwrite Passed to [tile_download()]: re-fetch tiles already cached.
#' @param max_active Passed to [tile_download()]: how many downloads to have
#'   in flight at once.
#' @param quiet Suppress progress.
#'
#' @return A `terra::SpatRaster`.
#'
#' @section What it refuses, and why:
#' \describe{
#'   \item{More than one vintage}{Orthophotos from different flights differ in
#'     sun angle, phenology and radiometry; the join shows as a visible seam,
#'     and the two halves are months or years apart in what they depict.}
#'   \item{More than one product}{A terrain model and a surface model are
#'     different quantities. Mosaicking them makes a surface that is neither.}
#'   \item{More than one composition}{RGB and false-colour infrared are both
#'     three bands, so they join without complaint, and band 1 then means two
#'     different things in two halves of the picture.}
#'   \item{More than one resolution}{One of them gets resampled, silently.}
#'   \item{More than one vertical datum}{PL-KRON86-NH and PL-EVRF2007-NH differ
#'     by tens of centimetres. The seam is a step in the terrain that is not
#'     there.}
#'   \item{Point clouds}{LAS and LAZ are not rasters. Use `lidR` or `PDAL`.}
#' }
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#' idx <- ortho_request(aoi)
#'
#' recent <- subset(idx, year == max(year) & composition == "RGB")
#' picture <- tile_mosaic(recent, aoi, crop = "aoi", mask = TRUE)
#' terra::plotRGB(picture)
#' }
#'
#' @seealso [tile_download()] to fetch without joining.
#' @export
tile_mosaic <- function(index, aoi = NULL, crop = c("aoi", "tiles"),
                        mask = FALSE, filename = NULL, allow_mixed = FALSE,
                        overwrite = FALSE, max_active = NULL,
                        quiet = FALSE) {
  crop <- match.arg(crop)
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is needed to mosaic rasters. Install it first.",
         call. = FALSE)
  }
  if (!is.data.frame(index) || nrow(index) == 0L) {
    stop("`index` must be a non-empty index from one of the *_request() ",
         "functions.", call. = FALSE)
  }
  if (crop == "aoi" && is.null(aoi)) {
    stop("`crop = \"aoi\"` needs an `aoi`. Pass one, or use crop = \"tiles\".",
         call. = FALSE)
  }
  if (!allow_mixed) check_mosaicable(index)

  # terra draws its own progress bar for the join. Honour `quiet` over it too,
  # and put the setting back afterwards rather than leaving the session changed.
  if (!progress_on(quiet)) {
    old_progress <- terra::terraOptions(print = FALSE)$progress
    terra::terraOptions(progress = 0)
    on.exit(terra::terraOptions(progress = old_progress), add = TRUE)
  }

  got <- tile_download(index, overwrite = overwrite, max_active = max_active,
                       quiet = quiet)
  files <- tile_raster_files(got)
  if (length(files) == 0L) {
    stop("None of the downloaded files is a raster this can join.", call. = FALSE)
  }

  say(quiet, "Joining ", length(files), " tile",
      if (length(files) == 1L) "" else "s", "...")
  rasters <- lapply(files, read_tile, epsg = index_epsg(index))
  out <- if (length(rasters) == 1L) {
    rasters[[1]]
  } else {
    terra::mosaic(terra::sprc(rasters), fun = "first")
  }

  if (crop == "aoi") {
    geom <- aoi_geom(as_aoi(aoi), crs = sf::st_crs(out)$epsg %||% CRS_PL1992)
    out <- terra::crop(out, terra::vect(geom))
    if (isTRUE(mask)) out <- terra::mask(out, terra::vect(geom))
  }

  if (!is.null(filename)) {
    say(quiet, "  writing ", basename(filename))
    out <- terra::writeRaster(out, filename, overwrite = TRUE)
  }
  out
}

# Every reason to refuse, checked together so the message can name all of them
# at once rather than one per re-run.
check_mosaicable <- function(index) {
  if ("product" %in% names(index) &&
      any(as.character(index$product) == "PointCloud", na.rm = TRUE)) {
    stop("Point clouds cannot be mosaicked as rasters. Filter them out, or ",
         "read the LAS/LAZ files with a point cloud package.", call. = FALSE)
  }

  columns <- c(product = "product", year = "vintage", composition = "band composition",
               resolution = "resolution", VRS = "vertical datum", CRS = "coordinate system")
  problems <- character(0)
  for (col in names(columns)) {
    if (!(col %in% names(index))) next
    vals <- unique(stats::na.omit(as.character(index[[col]])))
    if (length(vals) > 1L) {
      problems <- c(problems, paste0(columns[[col]], ": ",
                                     paste(sort(vals), collapse = ", ")))
    }
  }
  if (length(problems)) {
    stop(
      "These tiles do not belong in one mosaic. They disagree on\n  - ",
      paste(problems, collapse = "\n  - "),
      "\nFilter the index to one of each, or pass allow_mixed = TRUE if the ",
      "mixture is deliberate.",
      call. = FALSE
    )
  }

  # The same map sheet can appear more than once in one vintage, typically as a
  # partly filled sheet alongside the filled one. Joining both takes whichever
  # comes first, and where that is the unfilled version the mosaic comes out
  # with holes -- while `coverage()` still reports the area as fully covered,
  # because the sheet outlines do cover it.
  if ("sheetID" %in% names(index)) {
    dup <- unique(index$sheetID[duplicated(index$sheetID)])
    if (length(dup)) {
      hint <- if ("isFilled" %in% names(index) && any(!index$isFilled, na.rm = TRUE)) {
        paste0("\n  ", sum(!index$isFilled, na.rm = TRUE),
               " of them are marked not filled; subset(index, isFilled) ",
               "usually resolves this.")
      } else {
        "\n  Pick one series per sheet, for example with `seriesID`."
      }
      stop(
        length(dup), " map sheet", if (length(dup) == 1L) " appears" else "s appear",
        " more than once: ", paste(utils::head(dup, 5), collapse = ", "),
        if (length(dup) > 5) ", ..." else "", ".",
        "\n  Joining duplicates silently picks one of them, which is how a ",
        "mosaic ends up with holes.", hint,
        call. = FALSE
      )
    }
  }
  invisible(index)
}

# The EPSG code the tiles are in, taken from the index rather than the files,
# because ASCII grids do not carry one.
index_epsg <- function(index) {
  if (!("CRS" %in% names(index))) return(CRS_PL1992)
  vals <- unique(stats::na.omit(as.character(index$CRS)))
  if (length(vals) != 1L) return(NA_integer_)
  # `[[` on a named vector throws for an unknown name rather than returning
  # NULL, and a system this package has not seen yet must degrade, not stop.
  unname(INDEX_CRS[match(vals[1], names(INDEX_CRS))])
}

read_tile <- function(path, epsg) {
  r <- terra::rast(path)
  if (is.na(terra::crs(r, describe = TRUE)$code) && !is.na(epsg)) {
    terra::crs(r) <- paste0("EPSG:", epsg)
  }
  r
}

# A downloaded tile may be the raster itself, or an archive that was unpacked
# beside it.
tile_raster_files <- function(got) {
  out <- character(0)
  for (i in seq_len(nrow(got))) {
    candidates <- if (!is.na(got$extracted[i])) {
      list.files(got$extracted[i], full.names = TRUE, recursive = TRUE)
    } else {
      got$path[i]
    }
    out <- c(out, candidates[vapply(candidates, is_raster_file, logical(1))])
  }
  unique(out)
}

# The index gives orthophoto tiles names with no extension at all -- measured,
# `83832_1514566_N-33-130-D-a-4-3` is a GeoTIFF -- so the file has to be
# recognised by what is in it rather than by what it is called.
is_raster_file <- function(path) {
  if (!file.exists(path) || dir.exists(path)) return(FALSE)
  if (grepl("\\.(tif|tiff|asc|img|vrt)$", path, ignore.case = TRUE)) return(TRUE)
  if (grepl("\\.(zip|xml|txt|prj|gfs|aux|json|las|laz)$", path, ignore.case = TRUE)) {
    return(FALSE)
  }
  head_bytes <- readBin(path, "raw", n = 8)
  if (length(head_bytes) < 4L) return(FALSE)
  magic <- paste(sprintf("%02x", as.integer(head_bytes[1:4])), collapse = "")
  if (magic %in% c("49492a00", "4d4d002a")) return(TRUE)          # TIFF
  grepl("^ncols", rawToChar(head_bytes[head_bytes != as.raw(0)])) # ASCII grid
}
