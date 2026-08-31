# Canopy height ---------------------------------------------------------------
#
# Surface minus terrain, which is arithmetic, and three checks around it that
# are not:
#
#   the two rasters must sit on the same grid, or the subtraction resamples one
#   of them without saying so;
#
#   they must come from the same survey, or the difference is partly the change
#   between two flights;
#
#   the vertical datum cancels -- both halves are measured in it -- so a canopy
#   model is safe across the 2019 change of datum in a way that comparing two
#   terrain models is not.

#' Canopy height for an area
#'
#' Fetches the surface and terrain models over an area and subtracts one from
#' the other. `chm_get()` downloads both; `chm_build()` does the arithmetic on
#' rasters you already have.
#'
#' @param aoi An area of interest: anything [as_aoi()] accepts.
#' @param year Which survey to build the model from. `NULL`, the default,
#'   uses the coverage services, which publish the current model and hand it
#'   back already clipped. Naming a year instead assembles the model from
#'   archive tiles, which is the only way to reach an earlier flight.
#'   [chm_years()] lists the vintages an area can make one from.
#' @param resolution Pixel size in metres. Both models are requested at the
#'   same one, which is what puts them on the same grid. With `year` set this
#'   selects among the pixel sizes the archive actually holds, and falls back
#'   to the finest one available for that vintage.
#' @param max_active How many tiles to download at once, when `year` sends
#'   this through the archive. Ignored otherwise.
#' @param datum Vertical reference system, `"evrf2007"` or `"kron86"`. It
#'   cancels in the subtraction, so it matters only if you also want the inputs.
#' @param keep `"chm"` returns the canopy model alone; `"all"` returns a list
#'   of all three rasters, canopy, surface and terrain, when you want to look
#'   at what went into it.
#' @param min_height Heights below this become `NA`. `NULL`, the default,
#'   changes nothing. Setting it to `0` removes the small negative values that
#'   come from noise in the two models; note that this drops those cells rather
#'   than flattening them to zero, so it does not invent ground where there was
#'   none.
#' @param mask Cut the result to the outline of the area rather than to its
#'   bounding box, so a ragged stand comes back without its corners filled
#'   in. For [chm_build()] this needs `aoi` as well.
#' @param filename Write the canopy model here.
#' @param max_pixels Passed to [dem_get()]. Only the coverage route is
#'   bounded this way; tiles are already cut into sheets.
#' @param quiet Suppress progress.
#' @param gdal GDAL creation options for the written file, as a character
#'   vector. `NULL`, the default, writes DEFLATE with the predictor that suits
#'   the data, tiled, and BIGTIFF when the size calls for it. Pass your own to
#'   replace that wholesale -- for a Cloud Optimized GeoTIFF, say, or to turn
#'   compression off.
#'
#' @return A `terra::SpatRaster`, or with `keep = "all"` a list of three named
#'   `chm`, `surface` and `terrain`.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(c(16.80, 52.44), buffer = 400)
#'
#' canopy <- chm_get(aoi, resolution = 1)
#' terra::plot(canopy)
#'
#' # keep what went into it, and drop the noise below ground
#' parts <- chm_get(aoi, keep = "all", min_height = 0)
#' terra::plot(parts$surface)
#' }
#'
#' @seealso [dem_get()] for the models on their own, and [coverage()] to check
#'   whether a canopy model is possible from the archive at all -- these
#'   coverage services publish only the current one.
#' @export
chm_get <- function(aoi, year = NULL, resolution = 1,
                    datum = c("evrf2007", "kron86"),
                    keep = c("chm", "all"), min_height = NULL, mask = FALSE,
                    filename = NULL, max_active = NULL, max_pixels = 2500,
                    quiet = FALSE, gdal = NULL) {
  datum <- match.arg(datum)
  keep <- match.arg(keep)

  parts <- if (is.null(year)) {
    chm_from_coverage(aoi, resolution, datum, max_pixels, quiet)
  } else {
    chm_from_tiles(aoi, year, resolution, max_active, quiet)
  }

  chm_build(parts$surface, parts$terrain,
            aoi = if (isTRUE(mask)) aoi else NULL,
            keep = keep, min_height = min_height, mask = mask,
            filename = filename, quiet = quiet, gdal = gdal)
}

# The current model, straight from the coverage services, already clipped.
chm_from_coverage <- function(aoi, resolution, datum, max_pixels, quiet) {
  say(quiet, "Surface model...")
  surface <- dem_get(aoi, "dsm", resolution = resolution, datum = datum,
                     max_pixels = max_pixels, quiet = quiet)
  say(quiet, "Terrain model...")
  terrain <- dem_get(aoi, "dtm", resolution = resolution, datum = datum,
                     max_pixels = max_pixels, quiet = quiet)
  list(surface = surface, terrain = terrain)
}

# Any earlier survey, assembled from its tiles. The coverage services publish
# the current model and nothing else, so this is the only route to a canopy
# model of a particular flight -- and the one anybody who wants one has been
# walking by hand: two index filters, two mosaics, one subtraction.
chm_from_tiles <- function(aoi, year, resolution, max_active, quiet) {
  index <- dem_request(aoi, format = "grid", quiet = quiet)
  pair <- chm_pair(index, year, resolution)

  say(quiet, "Surface model: ", nrow(pair$surface), " tiles from ", year,
      " at ", pair$resolution, " m...")
  surface <- tile_mosaic(pair$surface, aoi, crop = "aoi",
                         max_active = max_active, quiet = quiet)
  say(quiet, "Terrain model: ", nrow(pair$terrain), " tiles...")
  terrain <- tile_mosaic(pair$terrain, aoi, crop = "aoi",
                         max_active = max_active, quiet = quiet)
  list(surface = surface, terrain = terrain)
}

# Surface and terrain have to come off the same grid, so the pixel size is
# settled once for the pair. Picking it twice independently is how you end up
# with a 1 m surface over a 0.5 m terrain and a subtraction that resamples.
chm_pair <- function(index, year, resolution) {
  have <- index[index$year == year &
                as.character(index$product) %in% c("DSM", "DTM"), , drop = FALSE]
  usable <- both_products(have)

  if (length(usable) == 0L) {
    stop("This area has no vintage from ", year,
         " with both a surface and a terrain model.",
         "\n  chm_years() lists the ones it does have.", call. = FALSE)
  }
  pick <- if (!is.null(resolution) && resolution %in% usable) resolution else min(usable)
  list(
    surface = one_per_sheet(product_at(have, "DSM", pick)),
    terrain = one_per_sheet(product_at(have, "DTM", pick)),
    resolution = pick
  )
}

product_at <- function(index, product, resolution) {
  index[as.character(index$product) == product &
        index$resolution == resolution, , drop = FALSE]
}

# The pixel sizes at which this selection holds both halves of the difference.
both_products <- function(index) {
  sizes <- sort(unique(stats::na.omit(index$resolution)))
  sizes[vapply(sizes, function(r) {
    all(c("DSM", "DTM") %in% as.character(index$product[index$resolution == r]))
  }, logical(1))]
}
#' @rdname chm_get
#' @param surface,terrain Surface and terrain models: file paths, or
#'   `terra::SpatRaster` objects.
#' @param aoi The area to cut to when `mask = TRUE`. Ignored otherwise.
#' @export
chm_build <- function(surface, terrain, aoi = NULL, keep = c("chm", "all"),
                      min_height = NULL, mask = FALSE, filename = NULL,
                      quiet = FALSE, gdal = NULL) {
  keep <- match.arg(keep)
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is needed to build a canopy model. Install it first.",
         call. = FALSE)
  }
  if (!is.null(min_height) &&
      (!is.numeric(min_height) || length(min_height) != 1L)) {
    stop("`min_height` must be a single number, or NULL.", call. = FALSE)
  }

  s <- as_raster(surface)
  t <- as_raster(terrain)
  check_same_grid(s, t)

  say(quiet, "Subtracting...")
  chm <- s - t
  if (!is.null(min_height)) chm[chm < min_height] <- NA
  if (isTRUE(mask)) {
    if (is.null(aoi)) {
      stop("`mask = TRUE` needs an `aoi` to cut to.", call. = FALSE)
    }
    geom <- aoi_geom(as_aoi(aoi), crs = raster_epsg(chm))
    chm <- terra::mask(terra::crop(chm, terra::vect(geom)), terra::vect(geom))
    say(quiet, "  masked to the area outline")
  }
  names(chm) <- "canopy_height"

  if (!is.null(filename)) {
    say(quiet, "  writing ", basename(filename))
    chm <- terra::writeRaster(chm, filename, overwrite = TRUE,
                              gdal = raster_gdal(chm, gdal))
  }
  if (keep == "all") {
    return(list(chm = chm, surface = s, terrain = t))
  }
  chm
}

as_raster <- function(x) {
  if (inherits(x, "SpatRaster")) return(x)
  if (is.character(x) && length(x) == 1L) return(open_raster(x))
  stop("Expected a file path or a SpatRaster, not ",
       paste(class(x), collapse = "/"), ".", call. = FALSE)
}

# terra will happily subtract rasters that do not line up, resampling one of
# them on the way and saying nothing. For a canopy model that turns a
# half-pixel offset into a rim of false height around every crown, so the
# mismatch is reported instead.
check_same_grid <- function(s, t, what = c("surface", "terrain")) {
  problems <- character(0)
  if (!identical(dim(s)[1:2], dim(t)[1:2])) {
    problems <- c(problems, sprintf(
      "size: %d x %d against %d x %d",
      terra::nrow(s), terra::ncol(s), terra::nrow(t), terra::ncol(t)))
  }
  if (!isTRUE(all.equal(terra::res(s), terra::res(t)))) {
    problems <- c(problems, sprintf(
      "resolution: %s against %s",
      paste(signif(terra::res(s), 6), collapse = " x "),
      paste(signif(terra::res(t), 6), collapse = " x ")))
  }
  if (!isTRUE(all.equal(as.vector(terra::ext(s)), as.vector(terra::ext(t)),
                        tolerance = 1e-6))) {
    problems <- c(problems, "extent: the two do not cover the same ground")
  }
  scrs <- terra::crs(s, describe = TRUE)$code
  tcrs <- terra::crs(t, describe = TRUE)$code
  if (!identical(scrs, tcrs)) {
    problems <- c(problems, sprintf("coordinate system: %s against %s",
                                    scrs %||% "none", tcrs %||% "none"))
  }
  if (length(problems)) {
    stop(
      "The ", what[1], " and ", what[2], " rasters are not on the same grid:",
      "\n  - ", paste(problems, collapse = "\n  - "),
      "\nRequest both through chm_get(), or align them yourself with ",
      "terra::resample() before subtracting.",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' Which vintages can make a canopy height model
#'
#' A canopy model is one survey's surface model minus its own terrain model,
#' so it needs a vintage that published both, at one pixel size. Not every one
#' did: the terrain has been remapped far more often than the surface, and a
#' year with a terrain model alone cannot make a canopy model at all.
#'
#' @param aoi An area of interest: anything [as_aoi()] accepts.
#' @param quiet Suppress progress.
#'
#' @return A data frame of `year`, `resolution` and the tile count of each
#'   model, newest first, holding only the combinations that have both.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(c(21.05, 53.80), buffer = 1000)
#'
#' chm_years(aoi)                       # what the archive can do here
#' canopy <- chm_get(aoi, year = 2014, mask = TRUE)
#' }
#'
#' @seealso [chm_get()] to build one, and [ortho_pairs()] for the same
#'   question asked of orthophotos.
#' @export
chm_years <- function(aoi, quiet = FALSE) {
  index <- dem_request(aoi, format = "grid", quiet = quiet)
  d <- as.data.frame(index)
  d <- d[as.character(d$product) %in% c("DSM", "DTM") & !is.na(d$resolution), ,
         drop = FALSE]

  combos <- unique(d[, c("year", "resolution")])
  rows <- lapply(seq_len(nrow(combos)), function(i) {
    sel <- d[d$year == combos$year[i], , drop = FALSE]
    ns <- nrow(one_per_sheet(product_at(sel, "DSM", combos$resolution[i])))
    nt <- nrow(one_per_sheet(product_at(sel, "DTM", combos$resolution[i])))
    if (ns == 0L || nt == 0L) return(NULL)
    data.frame(year = combos$year[i], resolution = combos$resolution[i],
               surface = ns, terrain = nt)
  })

  out <- do.call(rbind, rows)
  if (is.null(out)) {
    return(data.frame(year = integer(0), resolution = numeric(0),
                      surface = integer(0), terrain = integer(0)))
  }
  out[order(-out$year, out$resolution), , drop = FALSE]
}
