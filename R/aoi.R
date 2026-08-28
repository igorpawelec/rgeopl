# Area-of-interest normalisation -------------------------------------------
#
# Every service in this package is queried by a bounding box or a geometry,
# but each one wants it in its own CRS and its own syntax. `as_aoi()` is the
# single entry point that turns whatever the user has into one internal
# representation; `aoi_bbox()` and `aoi_geom()` then hand it to a client in
# the CRS that client needs.

# EPSG:2180 (PL-1992) is the working CRS: it is metric, it covers the whole
# country, and it is what the GUGiK services speak natively.
CRS_PL1992 <- 2180L
CRS_WGS84 <- 4326L

# Disjoint coordinate windows used to infer a CRS for bare numeric input.
PL_LONLAT <- c(xmin = 13.5, ymin = 48.5, xmax = 24.5, ymax = 55.2)
PL_1992 <- c(xmin = 1.4e5, ymin = 1.3e5, xmax = 8.8e5, ymax = 9.1e5)

#' Define an area of interest
#'
#' Normalises anything that describes a place in Poland into the internal
#' representation used by every client in this package.
#'
#' @param x One of: an `sf`, `sfc` or `sfg` object; an `sf` bounding box; a
#'   `SpatVector`, `SpatRaster` or `SpatExtent` (`terra`); a length-2 numeric
#'   vector (a single point, `c(x, y)`); a length-4 numeric vector (a bounding
#'   box, `c(xmin, ymin, xmax, ymax)`); a two-column matrix of coordinates; a
#'   path to any file `sf` can read; or a WKT string.
#' @param crs Coordinate reference system of `x`, for inputs that do not carry
#'   one. Anything `sf::st_crs()` accepts. When `NULL` (default) and `x` is
#'   bare numeric, the CRS is inferred from the coordinate range: values inside
#'   Poland's longitude/latitude window are read as EPSG:4326, values inside
#'   the PL-1992 window as EPSG:2180. The two windows do not overlap, so the
#'   guess is either unambiguous or it fails loudly.
#' @param buffer Buffer in metres applied to the geometry. Applied in
#'   EPSG:2180, so the distance is a true ground distance. A point with
#'   `buffer = 0` stays a point, which is what you want when asking which tile
#'   contains a given location.
#'
#' @return An object of class `rgeopl_aoi`.
#'
#' @examples
#' # a point given in lon/lat, CRS inferred
#' as_aoi(c(16.93, 52.41))
#'
#' # the same point with a 500 m buffer around it
#' as_aoi(c(16.93, 52.41), buffer = 500)
#'
#' # an explicit bounding box in PL-1992
#' as_aoi(c(571248, 151377, 572248, 152377), crs = 2180)
#'
#' @export
as_aoi <- function(x, crs = NULL, buffer = 0) {
  if (inherits(x, "rgeopl_aoi")) {
    if (buffer != 0) x <- new_aoi(buffer_geom(x$geom, buffer))
    return(x)
  }

  if (!is.numeric(buffer) || length(buffer) != 1L || is.na(buffer)) {
    stop("`buffer` must be a single number (metres).", call. = FALSE)
  }

  geom <- aoi_as_sfc(x, crs)

  if (length(geom) == 0L) {
    stop("The area of interest has no geometries.", call. = FALSE)
  }
  if (is.na(sf::st_crs(geom))) {
    stop(
      "The area of interest has no CRS. Pass one via `crs`, ",
      "for example crs = 2180 or crs = 4326.",
      call. = FALSE
    )
  }
  if (anyNA(sf::st_bbox(geom))) {
    stop("The area of interest has empty or invalid geometries.", call. = FALSE)
  }

  if (buffer != 0) geom <- buffer_geom(geom, buffer)
  new_aoi(geom)
}

#' @rdname as_aoi
#' @param aoi An `rgeopl_aoi` object.
#' @export
is_aoi <- function(aoi) inherits(aoi, "rgeopl_aoi")

new_aoi <- function(geom) {
  types <- as.character(sf::st_geometry_type(geom))
  type <- if (all(types %in% c("POINT", "MULTIPOINT"))) "point" else "area"
  structure(list(geom = geom, type = type), class = "rgeopl_aoi")
}

# Input dispatch ------------------------------------------------------------

aoi_as_sfc <- function(x, crs) {
  if (inherits(x, "sf")) return(sf::st_geometry(x))
  if (inherits(x, "sfc")) return(x)
  if (inherits(x, "sfg")) return(sf::st_sfc(x, crs = crs_or_na(crs)))
  if (inherits(x, "bbox")) return(sf::st_as_sfc(x))
  if (inherits(x, c("SpatVector", "SpatRaster", "SpatExtent"))) {
    return(terra_as_sfc(x, crs))
  }
  if (is.matrix(x)) return(matrix_as_sfc(x, crs))
  if (is.numeric(x)) return(numeric_as_sfc(x, crs))
  if (is.character(x) && length(x) == 1L) return(character_as_sfc(x, crs))

  stop(
    "Cannot interpret an object of class ", paste(class(x), collapse = "/"),
    " as an area of interest. See ?as_aoi for accepted inputs.",
    call. = FALSE
  )
}

terra_as_sfc <- function(x, crs) {
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is needed for this input. Install it first.",
         call. = FALSE)
  }
  if (inherits(x, "SpatExtent")) {
    if (is.null(crs)) {
      stop("A SpatExtent carries no CRS. Pass one via `crs`.", call. = FALSE)
    }
    e <- as.vector(x) # xmin, xmax, ymin, ymax
    return(numeric_as_sfc(c(e[1], e[3], e[2], e[4]), crs))
  }
  wkt <- terra::crs(x)
  if (inherits(x, "SpatRaster")) {
    e <- as.vector(terra::ext(x))
    return(numeric_as_sfc(c(e[1], e[3], e[2], e[4]),
                          if (nzchar(wkt)) wkt else crs))
  }
  out <- sf::st_as_sfc(sf::st_as_sf(x))
  if (is.na(sf::st_crs(out)) && !is.null(crs)) sf::st_crs(out) <- crs
  out
}

matrix_as_sfc <- function(x, crs) {
  if (ncol(x) != 2L) {
    stop("A coordinate matrix must have exactly two columns (x, y).",
         call. = FALSE)
  }
  crs <- crs %||% guess_crs(range(x[, 1]), range(x[, 2]))
  sf::st_sfc(lapply(seq_len(nrow(x)), function(i) sf::st_point(x[i, ])),
             crs = crs)
}

numeric_as_sfc <- function(x, crs) {
  x <- as.numeric(x)
  if (anyNA(x)) stop("Coordinates must not be NA.", call. = FALSE)

  if (length(x) == 2L) {
    crs <- crs %||% guess_crs(x[1], x[2])
    return(sf::st_sfc(sf::st_point(x), crs = crs))
  }
  if (length(x) == 4L) {
    if (x[1] > x[3] || x[2] > x[4]) {
      stop(
        "A bounding box must be c(xmin, ymin, xmax, ymax) with xmin <= xmax ",
        "and ymin <= ymax.",
        call. = FALSE
      )
    }
    crs <- crs %||% guess_crs(c(x[1], x[3]), c(x[2], x[4]))
    bb <- sf::st_bbox(c(xmin = x[1], ymin = x[2], xmax = x[3], ymax = x[4]),
                      crs = sf::st_crs(crs))
    return(sf::st_as_sfc(bb))
  }
  stop(
    "A numeric area of interest must have length 2 (a point) or 4 ",
    "(a bounding box), not ", length(x), ".",
    call. = FALSE
  )
}

character_as_sfc <- function(x, crs) {
  if (file.exists(x)) {
    out <- sf::st_geometry(sf::st_read(x, quiet = TRUE))
    if (is.na(sf::st_crs(out)) && !is.null(crs)) sf::st_crs(out) <- crs
    return(out)
  }
  # Check the shape of the string before handing it to GDAL, which otherwise
  # prints its own complaint on the way to failing.
  wkt_types <- paste(
    "POINT", "LINESTRING", "POLYGON", "MULTIPOINT", "MULTILINESTRING",
    "MULTIPOLYGON", "GEOMETRYCOLLECTION",
    sep = "|"
  )
  if (!grepl(paste0("^\\s*(SRID=\\d+;)?\\s*(", wkt_types, ")\\s*[ZM]*\\s*\\("),
             x, ignore.case = TRUE)) {
    stop("`", x, "` is neither an existing file nor valid WKT.", call. = FALSE)
  }
  out <- tryCatch(sf::st_as_sfc(x, crs = crs_or_na(crs)), error = function(e) NULL)
  if (is.null(out)) {
    stop("`", x, "` is neither an existing file nor valid WKT.", call. = FALSE)
  }
  out
}

# Infer a CRS from coordinate ranges, or refuse to.
guess_crs <- function(xs, ys) {
  inside <- function(w) {
    all(xs >= w[["xmin"]] & xs <= w[["xmax"]]) &&
      all(ys >= w[["ymin"]] & ys <= w[["ymax"]])
  }
  if (inside(PL_LONLAT)) return(CRS_WGS84)
  if (inside(PL_1992)) return(CRS_PL1992)
  stop(
    "Cannot infer a CRS: the coordinates fall outside both Poland's ",
    "longitude/latitude window and the PL-1992 window. Pass `crs` explicitly.",
    call. = FALSE
  )
}

crs_or_na <- function(crs) if (is.null(crs)) sf::NA_crs_ else sf::st_crs(crs)

buffer_geom <- function(geom, buffer) {
  metric <- sf::st_transform(geom, CRS_PL1992)
  sf::st_buffer(metric, buffer)
}

# Accessors -----------------------------------------------------------------

#' Geometry and bounding box of an area of interest
#'
#' @param aoi An `rgeopl_aoi` object, or anything [as_aoi()] accepts.
#' @param crs Target CRS. Defaults to EPSG:2180, the CRS the GUGiK services
#'   use natively.
#' @param by_feature When `TRUE`, return one bounding box per feature instead
#'   of a single box around all of them. Useful for scattered areas, where one
#'   overall box would cover far more ground than was asked for.
#'
#' @return `aoi_geom()` an `sfc`; `aoi_bbox()` a named numeric vector
#'   (`xmin`, `ymin`, `xmax`, `ymax`), or a list of them when `by_feature`.
#'
#' @examples
#' aoi <- as_aoi(c(16.93, 52.41), buffer = 250)
#' aoi_bbox(aoi)
#' aoi_bbox(aoi, crs = 4326)
#'
#' @export
aoi_geom <- function(aoi, crs = CRS_PL1992) {
  aoi <- as_aoi(aoi)
  if (is.null(crs)) return(aoi$geom)
  sf::st_transform(aoi$geom, sf::st_crs(crs))
}

#' @rdname aoi_geom
#' @export
aoi_bbox <- function(aoi, crs = CRS_PL1992, by_feature = FALSE) {
  geom <- aoi_geom(aoi, crs)
  if (!by_feature) return(as_bbox_vec(sf::st_bbox(geom)))
  lapply(seq_along(geom), function(i) as_bbox_vec(sf::st_bbox(geom[i])))
}

as_bbox_vec <- function(bb) {
  out <- as.numeric(bb)
  names(out) <- c("xmin", "ymin", "xmax", "ymax")
  out
}

#' @export
print.rgeopl_aoi <- function(x, ...) {
  bb <- aoi_bbox(x)
  epsg <- sf::st_crs(x$geom)$epsg
  cat("<rgeopl area of interest>\n")
  cat("  type:     ", x$type, "\n", sep = "")
  cat("  features: ", length(x$geom), "\n", sep = "")
  cat("  CRS:      ",
      if (is.na(epsg)) "non-EPSG" else paste0("EPSG:", epsg), "\n", sep = "")
  cat("  bbox:     ", paste(format(bb, trim = TRUE), collapse = ", "),
      " (EPSG:2180)\n", sep = "")
  invisible(x)
}
