# GUGiK index clients -------------------------------------------------------

SKOROWIDZE <- "https://mapy.geoportal.gov.pl/gprest/services/SkorowidzeFOTOMF/MapServer"

LAYER_ORTHO <- 3L
LAYER_DEM <- 4L
LAYER_POINTCLOUD <- 5L

# The service publishes one map sheet in several forms at once -- measured
# across three distant areas, 178 of 1028 sheet/product/vintage combinations
# come in more than one, and some in three. Only one of them is a raster:
#
#   ARC/INFO ASCII GRID   .asc    a grid, the thing you can mosaic
#   ASCII XYZ GRID        .zip    a text list of points
#   ASCII TBD             .zip    a text list of points
#   ESRI TIN              .zip    a triangulated model
#   Intergraph TTN        .ttn    a triangulated model
#   LAS, LAZ              .laz    a point cloud -- both labels, always .laz
#
# The labels on point clouds track the era rather than the file: everything
# from 2012 to 2019 is called LAS, everything from 2021 on LAZ, and all of it
# arrives compressed.
FORMAT_ALIASES <- list(
  grid  = "ARC/INFO ASCII GRID",
  xyz   = c("ASCII XYZ GRID", "ASCII TBD"),
  tin   = c("ESRI TIN", "Intergraph TTN"),
  cloud = c("LAS", "LAZ")
)

DEM_FIELDS <- c(
  "godlo", "akt_rok", "asortyment", "format", "char_przestrz",
  "blad_sr_wys", "blad_sr_syt", "uklad_xy", "uklad_h", "akt_data",
  "czy_ark_wypelniony", "zr_danych", "id_serie", "nazwa_pliku",
  "url_do_pobrania"
)

ORTHO_FIELDS <- c(
  "godlo", "akt_rok", "piksel", "kolor", "zr_danych", "uklad_xy",
  "akt_data", "czy_ark_wypelniony", "id_serie", "nazwa_pliku",
  "url_do_pobrania"
)

#' What elevation, point cloud and orthophoto data exist for an area
#'
#' Each function returns an index (a *skorowidz*): one row per tile that
#' intersects the area of interest, with its vintage, format and download link,
#' and the tile outline as geometry. Nothing is downloaded. Filter the index
#' however you like -- base R, `dplyr`, `sf::st_filter()` -- and pass what
#' survives to [tile_download()].
#'
#' The 1000-record ceiling on the underlying service is handled internally: the
#' record count is read first, and results are assembled by object id when the
#' area exceeds one page. A short result raises a warning rather than being
#' returned as though it were complete.
#'
#' @param aoi An area of interest: anything [as_aoi()] accepts.
#' @param format Which form of each sheet to keep. The service publishes one
#'   sheet in several at once, and only one of them is a raster, so a
#'   selection left unfiltered can look like two tiles where there is one.
#'   Shorthands: `"grid"` (ARC/INFO ASCII GRID, the only form you can
#'   mosaic), `"xyz"` (text lists of points), `"tin"` (triangulated models),
#'   `"cloud"` (LAS and LAZ, both of which arrive as `.laz`). A service label
#'   works too, for anything not covered by those. `NULL`, the default, keeps
#'   everything, which is what you want when the question is what exists.
#' @param within_aoi Keep only tiles that actually meet the area. The service
#'   filters by bounding box alone, so for anything other than a rectangle it
#'   also returns tiles that lie beside the area. Set `FALSE` for the raw
#'   bounding-box result.
#' @param by_feature Ask about each feature of the area separately, rather than
#'   about one bounding box drawn around all of them. `NULL`, the default,
#'   decides by comparing the two: scattered plots are asked about one at a
#'   time, a single area or a tight cluster in one request. The queries go out
#'   concurrently and their answers are cached per feature, so re-running a
#'   script over the same plots costs nothing.
#' @param max_active How many requests to have in flight at once when
#'   `by_feature` applies. Defaults to `getOption("rgeopl.max_active", 6)`,
#'   capped at 16. These are public services; the cap is deliberate.
#' @param quiet Suppress progress messages.
#'
#' @return An `sf` data frame, one row per tile, with columns:
#'   `sheetID` (the map sheet, *godlo*), `year`, `product`, `format`,
#'   `resolution`, `density`, `source`, `CRS`, `VRS`, `date`, `isFilled`,
#'   `seriesID`, `filename`, `URL`, and the tile outline in EPSG:2180.
#'   Elevation indexes add `avgElevErr` and `avgPlanarErr`; the orthophoto
#'   index adds `composition` instead.
#'
#'   `resolution` is a grid spacing in metres and `density` is a point density
#'   in points per square metre. The service reports both in one text field;
#'   they are split here because they are not comparable, and only one of them
#'   is ever set for a given row.
#'
#'   Column names follow `rgugik` so that existing scripts port with a rename
#'   of the function call alone.
#'
#' @section Vertical reference systems:
#' `VRS` is worth reading before mosaicking. Poland switched from
#' PL-KRON86-NH to PL-EVRF2007-NH, and both appear in the same small area:
#' tiles of different vintages can sit on different vertical datums, so
#' heights are not directly comparable across them. [tile_download()] warns
#' when a selection mixes the two.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#'
#' dem <- dem_request(aoi)
#' table(dem$year, dem$product)
#'
#' # the same sheets, in the one form that mosaics
#' grids <- dem_request(aoi, format = "grid")
#'
#' # the most recent LAZ point clouds only
#' library(dplyr)
#' laz <- dem |>
#'   filter(product == "PointCloud", format == "LAZ") |>
#'   slice_max(year, n = 1)
#'
#' plot_coverage(ortho_request(aoi), aoi = aoi)
#' tile_download(laz)
#' }
#'
#' @export
dem_request <- function(aoi, format = NULL, within_aoi = TRUE,
                        by_feature = NULL, max_active = NULL, quiet = FALSE) {
  select_format(
    gugik_index(aoi, LAYER_DEM, DEM_FIELDS, "elevation", within_aoi, by_feature,
                max_active, quiet),
    format, "elevation"
  )
}

#' @rdname dem_request
#' @export
pointcloud_request <- function(aoi, format = NULL, within_aoi = TRUE,
                               by_feature = NULL, max_active = NULL,
                               quiet = FALSE) {
  select_format(
    gugik_index(aoi, LAYER_POINTCLOUD, DEM_FIELDS, "point cloud", within_aoi,
                by_feature, max_active, quiet),
    format, "point cloud"
  )
}

#' @rdname dem_request
#' @export
ortho_request <- function(aoi, within_aoi = TRUE, by_feature = NULL,
                                     max_active = NULL, quiet = FALSE) {
  gugik_index(aoi, LAYER_ORTHO, ORTHO_FIELDS, "orthophoto", within_aoi, by_feature,
              max_active, quiet)
}

gugik_index <- function(aoi, layer, fields, what, within_aoi = TRUE,
                        by_feature = NULL, max_active = NULL, quiet = FALSE) {
  aoi <- as_aoi(aoi)
  if (!quiet) message("Querying the ", what, " index...")

  available <- arcgis_fields(SKOROWIDZE, layer)
  fields <- intersect(fields, available)

  by_feature <- by_feature %||% aoi_scattered(aoi)
  raw <- if (isTRUE(by_feature)) {
    say(quiet, "  ", length(aoi$geom), " features, asked one at a time")
    arcgis_query_each(SKOROWIDZE, layer, aoi, fields, n_active = max_active,
                      quiet = quiet)
  } else {
    arcgis_query(SKOROWIDZE, layer, aoi, fields, quiet = quiet)
  }
  out <- standardise_index(raw)

  if (within_aoi) {
    n_before <- nrow(out)
    out <- keep_touching_aoi(out, aoi)
    if (!quiet && nrow(out) < n_before) {
      message("  dropped ", n_before - nrow(out),
              " tiles that met the bounding box but not the area")
    }
  }

  if (!quiet) {
    if (nrow(out) == 0L) {
      message("  no ", what, " data for this area")
    } else {
      message("  ", nrow(out), " tiles, ", length(unique(out$year)),
              " vintages (", min(out$year, na.rm = TRUE), "-",
              max(out$year, na.rm = TRUE), ")")
    }
  }
  new_index(out, what)
}

# Column mapping ------------------------------------------------------------

INDEX_NAMES <- c(
  godlo = "sheetID",
  akt_rok = "year",
  asortyment = "product",
  format = "format",
  char_przestrz = "resolution",
  piksel = "resolution",
  kolor = "composition",
  zr_danych = "source",
  uklad_xy = "CRS",
  uklad_h = "VRS",
  blad_sr_wys = "avgElevErr",
  blad_sr_syt = "avgPlanarErr",
  akt_data = "date",
  czy_ark_wypelniony = "isFilled",
  id_serie = "seriesID",
  nazwa_pliku = "filename",
  url_do_pobrania = "URL"
)

INDEX_ORDER <- c(
  "sheetID", "year", "product", "format", "resolution", "density",
  "composition", "source", "CRS", "VRS", "avgElevErr", "avgPlanarErr",
  "date", "isFilled", "seriesID", "filename", "URL"
)

standardise_index <- function(x) {
  hit <- names(x) %in% names(INDEX_NAMES)
  names(x)[hit] <- INDEX_NAMES[names(x)[hit]]

  if ("product" %in% names(x)) {
    x$product <- factor(
      x$product,
      levels = c("NMT", "NMPT", "chmura punktow"),
      labels = c("DTM", "DSM", "PointCloud")
    )
  } else {
    x$product <- factor(rep("Orthophoto", nrow(x)))
  }

  if ("source" %in% names(x)) x$source <- factor(recode_source(x$source))

  if ("year" %in% names(x)) x$year <- as.integer(x$year)
  if ("isFilled" %in% names(x)) x$isFilled <- x$isFilled == "TAK"
  if ("date" %in% names(x)) x$date <- as_acquisition_date(x$date)
  for (v in c("avgElevErr", "avgPlanarErr")) {
    if (v %in% names(x)) x[[v]] <- suppressWarnings(as.numeric(x[[v]]))
  }
  x <- split_resolution(x)

  keep <- c(intersect(INDEX_ORDER, names(x)), attr(x, "sf_column"))
  x[, keep]
}

# The service records six kinds of source across the three indexes, and they
# matter: a terrain model traced off topographic maps is a different thing from
# one flown with a laser. Anything unrecognised is passed through with its
# original label rather than turned into NA -- a value silently going missing
# is worse than a Polish string in the output.
SOURCE_LABELS <- c(
  "Skaning laserowy" = "Laser scanning",
  "Zdj. lotnicze" = "Aerial photo",
  "Zdj. cyfrowe" = "Digital photo",
  "Zdj. analogowe" = "Analogue photo",
  "Scena sat." = "Satellite scene",
  "Mapy topograficzne" = "Topographic map"
)

recode_source <- function(x) {
  x <- as.character(x)
  hit <- match(x, names(SOURCE_LABELS))
  ifelse(is.na(hit), x, SOURCE_LABELS[hit])
}

# Acquisition dates arrive as midnight UTC. Read in the session's own time
# zone they fall a day early anywhere west of Greenwich, so the same index
# would date differently in Vancouver and in Warsaw. GDAL's Esri JSON reader
# already returns POSIXct; older paths hand over epoch milliseconds.
as_acquisition_date <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x, tz = "UTC"))
  as.Date(as.POSIXct(as.numeric(x) / 1000, origin = "1970-01-01", tz = "UTC"),
          tz = "UTC")
}

# `char_przestrz` carries two different quantities in one text field: a grid
# spacing for rasters ("1.00 m") and a point density for point clouds
# ("10 p/m2"). Parsed into one numeric column they would be indistinguishable,
# and a filter like resolution <= 1 would quietly select 1 m grids together
# with the sparsest clouds. They get a column each.
split_resolution <- function(x) {
  if (!("resolution" %in% names(x))) return(x)
  raw <- x$resolution
  if (is.numeric(raw)) {
    # the orthophoto index publishes a plain number, already in metres
    x$density <- NA_real_
    return(x)
  }
  raw <- as.character(raw)
  num <- suppressWarnings(as.numeric(sub("^\\s*([0-9.]+).*$", "\\1", raw)))
  is_density <- grepl("p/m2", raw, fixed = TRUE)

  x$resolution <- ifelse(is_density, NA_real_, num)
  x$density <- ifelse(is_density, num, NA_real_)
  x
}

new_index <- function(x, what = NULL) {
  attr(x, "rgeopl_what") <- what
  class(x) <- unique(c("rgeopl_index", class(x)))
  x
}

#' @export
print.rgeopl_index <- function(x, ...) {
  what <- attr(x, "rgeopl_what") %||% "index"
  cat("<rgeopl ", what, " index: ", nrow(x), " tiles>\n", sep = "")
  if (nrow(x) > 0L) {
    yrs <- sort(unique(x$year))
    cat("  vintages: ", paste(utils::head(yrs, 12), collapse = ", "),
        if (length(yrs) > 12) paste0(", ... (", length(yrs), " in total)") else "",
        "\n", sep = "")
    if ("product" %in% names(x)) {
      cat("  products: ",
          paste(names(table(droplevels(x$product))), collapse = ", "), "\n", sep = "")
    }
    if ("VRS" %in% names(x) && length(unique(x$VRS)) > 1L) {
      cat("  note:     mixed vertical datums (",
          paste(sort(unique(x$VRS)), collapse = ", "), ")\n", sep = "")
    }
  }
  print_without_class(x, "rgeopl_index", ...)
  invisible(x)
}

# Filtering on format is done here rather than left to the caller because the
# duplication is invisible until something downstream fails: two rows under one
# sheet number look like two tiles, not one tile in two shapes.
select_format <- function(index, format, what) {
  if (is.null(format)) return(index)
  if (!("format" %in% names(index))) return(index)

  wanted <- unlist(FORMAT_ALIASES[tolower(format)], use.names = FALSE)
  # Anything that is not one of the shorthands is taken as a service label, so
  # a format this package has not seen yet is still reachable.
  wanted <- c(wanted, format[!(tolower(format) %in% names(FORMAT_ALIASES))])

  keep <- as.character(index$format) %in% wanted
  if (!any(keep)) {
    available <- sort(unique(stats::na.omit(as.character(index$format))))
    stop("No ", what, " tiles here are in format ",
         paste(format, collapse = " or "), ".",
         if (length(available)) {
           paste0("\n  Available: ", paste(available, collapse = ", "), ".")
         },
         "\n  Shorthands: ", paste(names(FORMAT_ALIASES), collapse = ", "), ".",
         call. = FALSE)
  }
  index[keep, , drop = FALSE]
}
