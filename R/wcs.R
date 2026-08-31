# WCS coverages ---------------------------------------------------------------
#
# The other way to get elevation and imagery, and the one to reach for first
# when you want a surface rather than an archive. The index functions answer
# "what was flown here, and when"; these answer "give me the current model over
# this area", already clipped, with no tiles to mosaic.
#
# What the services actually offer, read from their own DescribeCoverage rather
# than assumed:
#
#   terrain, KRON86     GeoTIFF       (a separate endpoint, TIFF only)
#   terrain, EVRF2007   ASCII grid
#   surface, either     ASCII grid    -- there is no GeoTIFF surface model
#   orthophoto x 3      GeoTIFF
#
# There is no WCS for point clouds. A coverage service serves rasters; LAS and
# LAZ come from the tile index, through `pointcloud_request()`.

WCS_BASE <- "https://mapy.geoportal.gov.pl/wss/service/PZGIK"

# endpoint, coverage id, MIME type, file extension
WCS_COVERAGES <- list(
  dtm_evrf2007 = list("NMT/GRID1/WCS/DigitalTerrainModel",
                      "DTM_PL-EVRF2007-NH", "image/x-aaigrid", "asc"),
  dtm_kron86 = list("NMT/GRID1/WCS/DigitalTerrainModelFormatTIFF",
                    "DTM_PL-KRON86-NH_TIFF", "image/tiff", "tif"),
  dsm_evrf2007 = list("NMPT/GRID1/WCS/DigitalSurfaceModel",
                      "DSM_PL-EVRF2007-NH", "image/x-aaigrid", "asc"),
  dsm_kron86 = list("NMPT/GRID1/WCS/DigitalSurfaceModel",
                    "DSM_PL-KRON86-NH", "image/x-aaigrid", "asc"),
  ortho_standard = list("ORTO/WCS/StandardResolution",
                        "Orthoimagery_StandardResolution", "GEOTIFF", "tif"),
  ortho_high = list("ORTO/WCS/HighResolution",
                    "Orthoimagery_High_Resolution", "GEOTIFF", "tif"),
  ortho_true = list("ORTO/WCS/TrueOrto", "True_Orthoimagery", "GEOTIFF", "tif")
)

#' Download an elevation model or an orthophoto for an area
#'
#' Fetches the current model over an area of interest as a single raster, ready
#' to open. No tiles, no mosaicking, no vintage to choose: the coverage service
#' hands back exactly the extent you ask for.
#'
#' Use these when you want a surface to work with. Use [dem_request()] and
#' friends when you want to know what was flown and when, or when you need a
#' vintage other than the current one -- the coverage services publish only the
#' current model.
#'
#' @param aoi An area of interest: anything [as_aoi()] accepts. The raster
#'   covers its bounding box, so a non-rectangular area comes back with its
#'   corners filled in.
#' @param product Which model. `"dtm"` is bare ground, `"dsm"` is the surface
#'   including vegetation and buildings; subtracting one from the other over the
#'   same year is a canopy height model. For [ortho_get()]: `"standard"`,
#'   `"high"` or `"true"` (true orthophoto, buildings corrected to nadir).
#' @param resolution Pixel size in metres. Defaults to 1 m for elevation and
#'   0.25 m for orthophotos, which is roughly the native detail of each.
#' @param datum Vertical reference system for elevation: `"evrf2007"` (the
#'   current national system) or `"kron86"` (the older one). Ignored for
#'   orthophotos.
#' @param filename Where to save it. `NULL` puts it in the cache and returns
#'   that path.
#' @param file Former name of `filename`, kept working for now. Everything
#'   else in the package says `filename`, and one idea should not answer to
#'   two words.
#' @param convert Convert an ASCII grid to GeoTIFF after downloading, which is
#'   lossless and strictly better: about a quarter of the size, and with the
#'   coordinate system attached. On by default; needs `terra`, and quietly
#'   keeps the ASCII grid if it is not installed. Orthophotos and the KRON86
#'   terrain model already arrive as GeoTIFF and are untouched.
#' @param mask Cut the result to the outline of the area, not just to its
#'   bounding box. The coverage services are addressed by a bounding box, so
#'   without this a ragged area comes back with its corners filled in. Needs
#'   `terra`.
#' @param max_pixels Refuse requests larger than this many pixels per side.
#'   Measured on the terrain service: 1000 px returns in a second or two, 2000
#'   px in under a minute, and 4000 px does not return at all. Raise it
#'   knowing that.
#' @param quiet Suppress progress messages.
#'
#' @return The path to the raster: a GeoTIFF unless `convert = FALSE` left an
#'   ASCII grid, which [open_raster()] will open with its coordinate system
#'   attached.
#'
#' @section Formats:
#' The format is not a choice, it is a consequence of what each service
#' publishes: the terrain model in KRON86 comes as GeoTIFF, everything else on
#' the elevation side as ASCII grid, and orthophotos as GeoTIFF. ASCII grids are
#' bulky -- a 1 km square at 1 m is about 16 MB against 4 MB for the same thing
#' as GeoTIFF -- so convert once and keep the conversion if you are going to use
#' it repeatedly.
#'
#' ASCII grids also carry no projection. `terra::rast()` opens them with a CRS
#' of `NA`, and a `.prj` sidecar does not help: GDAL's ASCII grid driver
#' ignores it, in WKT2 and in ESRI WKT1 alike. Both problems are why
#' `convert = TRUE` is the default. Use [open_raster()] for anything fetched
#' with `convert = FALSE`, or for ASCII grids from elsewhere.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(c(16.93, 52.41), buffer = 500)
#'
#' terrain <- open_raster(dem_get(aoi, "dtm"))
#' surface <- open_raster(dem_get(aoi, "dsm"))
#' picture <- open_raster(ortho_get(aoi, "high"))
#'
#' canopy <- surface - terrain
#' terra::plot(canopy)
#' }
#'
#' @export
dem_get <- function(aoi, product = c("dtm", "dsm"), resolution = 1,
                    datum = c("evrf2007", "kron86"), filename = NULL,
                    convert = TRUE, mask = FALSE, max_pixels = 2500,
                    quiet = FALSE, file = NULL) {
  product <- match.arg(product)
  datum <- match.arg(datum)
  wcs_get(paste(product, datum, sep = "_"), aoi, resolution,
          renamed_file(filename, file), convert, mask, max_pixels, quiet)
}

#' @rdname dem_get
#' @export
ortho_get <- function(aoi, product = c("standard", "high", "true"),
                      resolution = 0.25, filename = NULL, convert = TRUE,
                      mask = FALSE, max_pixels = 2500, quiet = FALSE,
                      file = NULL) {
  product <- match.arg(product)
  wcs_get(paste0("ortho_", product), aoi, resolution,
          renamed_file(filename, file), convert, mask, max_pixels, quiet)
}

# `file` was the name these two used until 0.5.0. It keeps working, with a
# word about it, because silently ignoring an argument someone passed is worse
# than the inconsistency it replaces.
renamed_file <- function(filename, file) {
  if (is.null(file)) return(filename)
  rlang::warn(c(
    "`file` has been renamed to `filename`.",
    i = "It still works for now, and will be removed in a later release."
  ))
  filename %||% file
}

wcs_get <- function(key, aoi, resolution, filename, convert, mask, max_pixels,
                    quiet) {
  spec <- WCS_COVERAGES[[key]]
  if (is.null(spec)) stop("No coverage called `", key, "`.", call. = FALSE)

  bbox <- aoi_bbox(as_aoi(aoi), crs = CRS_PL1992)
  size <- wcs_grid_size(bbox, resolution, max_pixels)

  url <- paste0(WCS_BASE, "/", spec[[1]])
  params <- list(
    SERVICE = "WCS", VERSION = "1.0.0", REQUEST = "GetCoverage",
    COVERAGE = spec[[2]], FORMAT = spec[[3]],
    BBOX = paste(round(bbox, 2), collapse = ","),
    CRS = "EPSG:2180", RESPONSE_CRS = "EPSG:2180",
    WIDTH = size[["width"]], HEIGHT = size[["height"]]
  )

  if (!quiet) {
    message("Requesting ", spec[[2]], ": ", size[["width"]], " x ",
            size[["height"]], " px at ", resolution, " m")
  }

  name <- paste0(tolower(gsub("[^A-Za-z0-9]+", "_", spec[[2]])), "_",
                 round(bbox[["xmin"]]), "_", round(bbox[["ymin"]]), "_",
                 size[["width"]], "x", size[["height"]], ".", spec[[4]])
  full_url <- httr2::req_url_query(httr2::request(url), !!!params)$url

  path <- gp_download(full_url, group = sub("_.*", "", key), filename = name,
                      label = spec[[2]], quiet = quiet)
  wcs_check(path)
  if (isTRUE(convert)) path <- to_geotiff(path, quiet = quiet)
  if (isTRUE(mask)) path <- mask_to_aoi(path, aoi, quiet = quiet)

  if (!is.null(filename)) {
    file.copy(path, filename, overwrite = TRUE)
    return(filename)
  }
  path
}

# ASCII grid is worse than GeoTIFF in every respect that matters here: about
# four times the size for the same data, and no coordinate system at all. The
# conversion is lossless, so it is done by default and the result kept beside
# the original, ready for the next call.
to_geotiff <- function(path, quiet = FALSE) {
  if (tolower(tools::file_ext(path)) != "asc") return(path)

  tif <- sub("\\.asc$", ".tif", path, ignore.case = TRUE)
  if (file.exists(tif)) return(tif)

  if (!requireNamespace("terra", quietly = TRUE)) {
    say(quiet,
        "  install 'terra' to convert ASCII grids to GeoTIFF automatically; ",
        "keeping the ASCII grid")
    return(path)
  }

  r <- terra::rast(path)
  terra::crs(r) <- paste0("EPSG:", CRS_PL1992)
  terra::writeRaster(r, tif, overwrite = TRUE, gdal = raster_gdal(r))
  say(quiet, "  converted to GeoTIFF (",
      format_bytes(file.size(path)), " -> ", format_bytes(file.size(tif)), ")")
  tif
}

# Pixels per side, from the extent and the requested ground resolution.
wcs_grid_size <- function(bbox, resolution, max_pixels) {
  if (!is.numeric(resolution) || length(resolution) != 1L || resolution <= 0) {
    stop("`resolution` must be a single positive number, in metres.",
         call. = FALSE)
  }
  w <- ceiling((bbox[["xmax"]] - bbox[["xmin"]]) / resolution)
  h <- ceiling((bbox[["ymax"]] - bbox[["ymin"]]) / resolution)
  if (max(w, h) > max_pixels) {
    stop(
      "That would be ", w, " x ", h, " pixels, over the ", max_pixels,
      " limit. Use a coarser `resolution`, a smaller area, or raise ",
      "`max_pixels` knowing the service stops answering above about 2000.",
      call. = FALSE
    )
  }
  c(width = max(w, 1L), height = max(h, 1L))
}

# A coverage service reports failure as an XML document with HTTP 200, which
# would otherwise be cached and handed back as if it were a raster.
wcs_check <- function(path) {
  head_bytes <- readBin(path, "raw", n = 200)
  if (length(head_bytes) == 0L) return(invisible(path))
  if (identical(as.integer(head_bytes[1:2]), c(0x3cL, 0x3fL))) {
    txt <- rawToChar(head_bytes[!head_bytes == as.raw(0)])
    unlink(path)
    rlang::abort(
      c("The coverage service returned an error instead of a raster.",
        i = trimws(gsub("\\s+", " ", substr(txt, 1, 200)))),
      class = "rgeopl_service_error"
    )
  }
  invisible(path)
}

# The coverage services take a bounding box, so a ragged area comes back as a
# rectangle. Masking is done here rather than left to the caller, so that
# `mask` means the same thing on this side as it does on `tile_mosaic()`.
mask_to_aoi <- function(path, aoi, quiet = FALSE) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    say(quiet, "  install 'terra' to mask to the outline; keeping the bounding box")
    return(path)
  }
  out <- paste0(tools::file_path_sans_ext(path), "_masked.",
                tools::file_ext(path))
  if (file.exists(out)) return(out)

  r <- open_raster(path)
  geom <- aoi_geom(as_aoi(aoi), crs = raster_epsg(r))
  r <- terra::mask(r, terra::vect(geom))
  terra::writeRaster(r, out, overwrite = TRUE, gdal = raster_gdal(r))
  say(quiet, "  masked to the area outline")
  out
}
