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
#' @param gdal GDAL creation options for the written file, as a character
#'   vector. `NULL`, the default, writes DEFLATE with the predictor that suits
#'   the data, tiled, and BIGTIFF when the size calls for it. Pass your own to
#'   replace that wholesale -- for a Cloud Optimized GeoTIFF, say, or to turn
#'   compression off.
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
#'   \item{More than one file format}{Every elevation sheet is published both
#'     as a grid and as a list of points, under the same sheet number. The
#'     point list is not a raster, so half such a mosaic would simply be
#'     missing.}
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
                        quiet = FALSE, gdal = NULL) {
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
  out <- join_tiles(files, epsg = index_epsg(index))

  if (crop == "aoi") {
    geom <- aoi_geom(as_aoi(aoi), crs = sf::st_crs(out)$epsg %||% CRS_PL1992)
    out <- terra::crop(out, terra::vect(geom))
    if (isTRUE(mask)) out <- terra::mask(out, terra::vect(geom))
  }

  out <- name_layers(out, index)

  if (!is.null(filename)) {
    say(quiet, "  writing ", basename(filename))
    out <- terra::writeRaster(out, filename, overwrite = TRUE,
                              gdal = raster_gdal(out, gdal))
  }
  out
}

# Without this the layers are called after the temporary VRT the mosaic was
# built through -- filedc437e7148b, and that string is written into the file as
# the band description, where it outlives the session that produced it. The
# index knows what these bands are.
name_layers <- function(x, index) {
  n <- terra::nlyr(x)
  comp <- if ("composition" %in% names(index)) {
    unique(stats::na.omit(as.character(index$composition)))
  } else character(0)

  nm <- if (n == 3L && identical(comp, "RGB")) {
    c("R", "G", "B")
  } else if (n == 3L && identical(comp, "CIR")) {
    # false colour infrared: near infrared, red, green
    c("NIR", "R", "G")
  } else if (n == 1L && "product" %in% names(index)) {
    unique(stats::na.omit(as.character(index$product)))
  } else {
    NULL
  }

  if (length(nm) == n) names(x) <- nm
  x
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
               resolution = "resolution", VRS = "vertical datum", CRS = "coordinate system",
               format = "file format")
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
      } else if ("format" %in% names(index) &&
                 length(unique(stats::na.omit(as.character(index$format)))) > 1L) {
        # The elevation models are published both as a grid and as a list of
        # points under the same sheet number, so this is the usual reason.
        fmts <- sort(unique(stats::na.omit(as.character(index$format))))
        paste0("\n  They are the same sheets in ", length(fmts),
               " formats: ", paste(fmts, collapse = ", "),
               ".\n  Pick one, for example ",
               "subset(index, format == \"", fmts[1], "\").")
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

# The tiles are joined through a GDAL virtual raster rather than by reading
# each one in and sticking them together. A VRT is a few kilobytes of XML
# naming the files and saying where each sits; whatever comes next -- a crop to
# the area, a write to disk -- then reads only the blocks it actually needs.
#
# Measured on 15 orthophoto tiles, 586 MB, cut to an 800 m square: 175 s the
# old way against 0.8 s this way, and not one cell of 17.3 million differs. The
# old way also built the entire join before cropping it, which for those tiles
# meant asking the disk for 17 GB of uncompressed scratch space -- enough to
# fail outright on a machine that has less.
join_tiles <- function(files, epsg) {
  if (length(files) == 1L) return(read_tile(files, epsg))

  # GDAL paints VRT sources in order, so a later one covers an earlier one
  # where they overlap. That is the opposite of mosaic(fun = "first"), which
  # this replaced. Reversing the list restores it: the first tile still wins.
  path <- tempfile(fileext = ".vrt")
  out <- suppressWarnings(terra::vrt(rev(files), filename = path,
                                     overwrite = TRUE))
  check_vrt_complete(path, length(files))
  set_missing_crs(out, epsg)
}

# terra::vrt() leaves out any file it cannot fit, and says so in a warning that
# scrolls past, leaving a mosaic with a hole in it that looks finished.
# Measured on what it actually rejects: a tile with a different number of bands
# and a tile in a different coordinate system are both dropped, while different
# resolutions and offset grids are accepted and resampled -- those are caught
# earlier, by check_mosaicable(). The VRT lists what it took, so it can be
# counted.
check_vrt_complete <- function(path, expected) {
  used <- length(vrt_sources(path))
  if (used >= expected) return(invisible(TRUE))
  stop(
    "Only ", used, " of ", expected, " tiles could be joined.",
    "\n  The rest differ in a way a virtual raster cannot bridge: another ",
    "number of bands, or another coordinate system.",
    "\n  Joining them anyway would leave holes where those tiles belong.",
    call. = FALSE
  )
}

# The files a VRT ended up using. Counted as distinct names rather than as
# lines, because a multi-band source is listed once per band -- three bands
# would otherwise pass for three tiles.
vrt_sources <- function(path) {
  lines <- grep("SourceFilename", readLines(path, warn = FALSE), fixed = TRUE,
                value = TRUE)
  unique(sub(".*<SourceFilename[^>]*>([^<]*)</SourceFilename>.*", "\\1", lines))
}

read_tile <- function(path, epsg) {
  set_missing_crs(terra::rast(path), epsg)
}

# ASCII grid tiles carry no projection of their own, so it comes from the index
# instead. Tiles that do declare one are left alone.
set_missing_crs <- function(r, epsg) {
  if (is.na(terra::crs(r, describe = TRUE)$code) && !is.na(epsg)) {
    terra::crs(r) <- paste0("EPSG:", epsg)
  }
  r
}

# A downloaded tile may be the raster itself, or an archive that was unpacked
# beside it.
tile_files <- function(got, keep) {
  out <- character(0)
  for (i in seq_len(nrow(got))) {
    candidates <- if (!is.na(got$extracted[i])) {
      list.files(got$extracted[i], full.names = TRUE, recursive = TRUE)
    } else {
      got$path[i]
    }
    out <- c(out, candidates[vapply(candidates, keep, logical(1))])
  }
  unique(out)
}

tile_raster_files <- function(got) tile_files(got, is_raster_file)

# One row per map sheet, which is what a mosaic needs. A sheet can appear more
# than once in a single vintage -- typically a partly filled sheet published
# alongside the filled one -- and taking whichever came first is how a mosaic
# ends up with holes.
one_per_sheet <- function(index) {
  if ("isFilled" %in% names(index) && any(index$isFilled, na.rm = TRUE)) {
    index <- index[which(index$isFilled), , drop = FALSE]
  }
  if (!("sheetID" %in% names(index))) return(index)
  index[!duplicated(index$sheetID), , drop = FALSE]
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
