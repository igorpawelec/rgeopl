# Vertical datums -------------------------------------------------------------
#
# Poland changed the system its heights are measured in, and the archive holds
# both: a 2014 tile is in PL-KRON86-NH, a 2022 one in PL-EVRF2007-NH, and the
# index says which in its VRS column. Measured across the country, EVRF2007
# heights run from 13.6 to 19.2 cm above KRON86 ones, so subtracting one
# terrain model from another across that boundary reports a settlement or an
# uplift that never happened.
#
# Converting between them ought to be a call to sf::st_transform(), and this is
# the reason it is not. PROJ knows the right transformation -- EPSG lists it at
# 0.04 m -- but the grid it needs, gugik-evrf2007.txt, is not among the files
# PROJ can fetch. Asked to convert anyway, PROJ offers a second candidate and
# takes it:
#
#   candidate 1   accuracy 0.04 m   instantiable: FALSE
#   candidate 2   accuracy NA       instantiable: TRUE    +proj=noop
#
# +proj=noop does nothing. The heights come back unchanged and relabelled,
# which is worse than an error, because nothing about the result looks wrong.
#
# What PROJ can fetch is the pair of quasi-geoid models GUGiK publishes, one
# per height system, 0.03 m each and openly licensed. Going up to the
# ellipsoid through one and back down through the other gives the conversion
# the direct grid would have given.

GEOID_GRIDS <- c(
  kron86 = "pl_gugik_geoid2011-PL-KRON86-NH.tif",
  evrf2007 = "pl_gugik_geoid2011-PL-EVRF2007-NH.tif"
)

#' Convert an elevation model between Poland's two height systems
#'
#' Heights measured in PL-KRON86-NH and in PL-EVRF2007-NH are not comparable.
#' Measured over Poland, an EVRF2007 height is 13.6 to 19.2 cm above the
#' KRON86 height of the same ground, and by how much depends on where you
#' are. The archive holds both, so any comparison of terrain spanning the
#' 2019 change of datum needs one side converted first.
#'
#' A canopy height model does not: surface and terrain are measured in the same
#' system and it cancels in the subtraction. This is for comparing *terrain*
#' with terrain -- subsidence, erosion, earthworks -- where the datum does not
#' cancel and about 17 cm of phantom change is the result of ignoring it.
#'
#' @param x An elevation model: a `terra::SpatRaster` or a path to one.
#' @param from,to The height systems, `"kron86"` for PL-KRON86-NH and
#'   `"evrf2007"` for PL-EVRF2007-NH. The index reports which a tile is in, in
#'   its `VRS` column.
#' @param step How finely to sample the shift, in metres. The shift is the
#'   difference of two quasi-geoid models and changes by 5.5 cm over the whole
#'   country, so it is sampled on a lattice and interpolated between samples
#'   rather than computed per cell. Measured against a 250 m lattice, the
#'   default 1000 m costs at most 0.67 mm and 2000 m costs 1.3 mm -- against
#'   models that are themselves accurate to 30 mm.
#' @param filename Write the result here.
#' @param quiet Suppress progress.
#' @param gdal GDAL creation options for the written file, as a character
#'   vector. `NULL`, the default, writes DEFLATE with the predictor that suits
#'   the data, tiled, and BIGTIFF when the size calls for it. Pass your own to
#'   replace that wholesale -- for a Cloud Optimized GeoTIFF, say, or to turn
#'   compression off.
#'
#' @return A `terra::SpatRaster` of the same geometry as `x`, with heights in
#'   the `to` system.
#'
#' @section What it needs, and what it refuses:
#' The two quasi-geoid grids are downloaded from PROJ's own content delivery
#' network the first time they are used, and cached by PROJ afterwards. This
#' function turns that network on for the duration of the call and puts the
#' setting back as it found it.
#'
#' It fails rather than guesses in three cases: the grids cannot be reached,
#' the area lies outside their coverage, or the computed shift is exactly zero
#' everywhere -- which is what a silent `+proj=noop` looks like from here.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(c(21.05, 53.80), buffer = 1000)
#' idx <- dem_request(aoi, format = "grid")
#'
#' # a 2014 terrain model is in PL-KRON86-NH
#' old <- tile_mosaic(subset(idx, product == "DTM" & year == 2014), aoi)
#' old_evrf <- dem_to_datum(old, from = "kron86", to = "evrf2007")
#'
#' # now it can be compared with a model published in the current system
#' terra::plot(old_evrf - old)   # the shift itself, about 0.16 m here
#' }
#'
#' @seealso [dem_request()], whose `VRS` column says which system a tile is in,
#'   and [chm_get()], which does not need this.
#' @export
dem_to_datum <- function(x, from = c("kron86", "evrf2007"),
                         to = c("evrf2007", "kron86"), step = 1000,
                         filename = NULL, quiet = FALSE, gdal = NULL) {
  from <- match.arg(from)
  to <- match.arg(to)
  if (identical(from, to)) {
    stop("`from` and `to` are the same system; there is nothing to convert.",
         call. = FALSE)
  }
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is needed to convert an elevation model.",
         call. = FALSE)
  }

  r <- as_raster(x)
  if (is.na(sf::st_crs(r))) {
    stop("`x` has no coordinate system, so its cells cannot be located.",
         "\n  open_raster() attaches one to the ASCII grids this archive ",
         "publishes.", call. = FALSE)
  }

  say(quiet, "Sampling the shift between ", from, " and ", to, "...")
  shift <- shift_field(r, from, to, step, quiet)

  say(quiet, "Applying it...")
  out <- r + terra::resample(shift, r, method = "bilinear")
  names(out) <- names(r)

  if (!is.null(filename)) {
    say(quiet, "  writing ", basename(filename))
    out <- terra::writeRaster(out, filename, overwrite = TRUE,
                              gdal = raster_gdal(out, gdal))
  }
  out
}

# The shift is smooth -- it is the difference of two quasi-geoid models -- so it
# is computed on a coarse lattice and interpolated, rather than at every cell.
# A national terrain model at 1 m is tens of millions of cells, and PROJ would
# be asked to place every one of them.
shift_field <- function(r, from, to, step, quiet = FALSE) {
  lattice <- terra::rast(terra::ext(r), crs = terra::crs(r),
                         resolution = lattice_step(r, step))
  terra::values(lattice) <- 0

  pts <- terra::as.points(lattice)
  ll <- sf::st_transform(sf::st_as_sf(pts), CRS_WGS84)
  xy <- sf::st_coordinates(ll)

  z <- vertical_shift(xy[, 1], xy[, 2], from, to)
  if (anyNA(z)) {
    stop(sum(is.na(z)), " of ", length(z), " sample points fall outside the ",
         "quasi-geoid models.",
         "\n  They cover Poland; an area reaching past the border cannot be ",
         "converted this way.", call. = FALSE)
  }
  # A shift of exactly nothing, everywhere, is what +proj=noop leaves behind.
  if (all(z == 0)) {
    stop("The conversion produced no shift at all, which means PROJ fell back ",
         "to a no-op instead of using the quasi-geoid models.", call. = FALSE)
  }
  say(quiet, "  ", length(z), " sample points, shift ",
      sprintf("%+.3f to %+.3f m", min(z), max(z)))

  terra::values(lattice) <- z
  lattice
}

# At least a few samples across the raster, however small it is, and never
# finer than the raster itself.
lattice_step <- function(r, step) {
  span <- c(terra::xmax(r) - terra::xmin(r), terra::ymax(r) - terra::ymin(r))
  pmax(pmin(step, span / 3), terra::res(r))
}

# Up to the ellipsoid through one quasi-geoid model and back down through the
# other. Both grids come from PROJ's network, which is switched on here and
# restored afterwards rather than left changed for the session.
vertical_shift <- function(lon, lat, from, to) {
  if (!sf::sf_proj_network()) {
    on.exit(sf::sf_proj_network(FALSE), add = TRUE)
    sf::sf_proj_network(TRUE)
  }

  # The axisswap steps are not decoration. Given a pipeline, sf hands PROJ the
  # coordinates in the authority axis order, which for EPSG:4326 is latitude
  # first, while vgridshift wants longitude first. Without the swap the grids
  # are sampled somewhere else entirely: checked against the two models read
  # directly, this pipeline agrees to 0.0000 m, and a version that routes
  # through PL-1992 instead -- where the authority order is northing first --
  # is out by up to 11 mm and returns nothing at all for Zakopane.
  pipe <- paste(
    "+proj=pipeline",
    "+step +proj=axisswap +order=2,1",
    "+step +proj=unitconvert +xy_in=deg +xy_out=rad",
    paste0("+step +proj=vgridshift +grids=", GEOID_GRIDS[[from]], " +multiplier=1"),
    paste0("+step +inv +proj=vgridshift +grids=", GEOID_GRIDS[[to]], " +multiplier=1"),
    "+step +proj=unitconvert +xy_in=rad +xy_out=deg",
    "+step +proj=axisswap +order=2,1"
  )

  g <- sf::st_sfc(lapply(seq_along(lon), function(i) {
    sf::st_point(c(lon[i], lat[i], 0))
  }), crs = CRS_WGS84)

  # sf warns that the pipeline is not one PROJ suggested. That is the point:
  # what PROJ suggests here is +proj=noop.
  out <- tryCatch(
    suppressWarnings(sf::st_transform(g, crs = "EPSG:4326", pipeline = pipe)),
    error = function(e) {
      stop("The quasi-geoid models could not be used: ", conditionMessage(e),
           "\n  They are fetched from https://cdn.proj.org the first time; ",
           "this needs network access.", call. = FALSE)
    }
  )
  sf::st_coordinates(out)[, "Z"]
}
