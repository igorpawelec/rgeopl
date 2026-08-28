#' Draw forest units, with context
#'
#' A quick look at whatever a lookup returned, so you can see where it is
#' before doing anything with it. Draws the units filled and labelled, over an
#' optional context layer in grey.
#'
#' @param x Units to draw: anything from [bdl_unit()], [bdl_by_address()],
#'   [bdl_subareas()] and friends, or any `sf` object.
#' @param label Column to label the units with. `NULL` picks the most specific
#'   name or code the table carries; `NA` labels nothing, which is what you
#'   want for hundreds of subareas.
#' @param context An `sf` layer drawn underneath in grey, typically the unit
#'   one level up. Also sets the extent, so the units are shown in place
#'   rather than filling the frame.
#' @param fill,border Colours for the units.
#' @param main Title. `NULL` builds one from the object.
#' @param ... Passed to [graphics::plot()].
#'
#' @return `x`, invisibly.
#'
#' @examples
#' \dontrun{
#' bircza <- bdl_unit(inspectorate = "Bircza")
#' plot_units(bdl_ranges(bircza), context = bircza)
#'
#' turnica <- bdl_by_address("04-02-2-11")
#' plot_units(turnica, context = bircza)
#' }
#'
#' @export
plot_units <- function(x, label = NULL, context = NULL, fill = "#a8d5ba",
                       border = "#3f7f5f", main = NULL, ...) {
  if (!inherits(x, "sf")) {
    stop("`x` must be an sf object.", call. = FALSE)
  }
  if (nrow(x) == 0L) stop("Nothing to draw: `x` has no rows.", call. = FALSE)

  if (is.null(main)) {
    what <- attr(x, "rgeopl_what") %||% "units"
    main <- paste0(nrow(x), " ", what)
  }

  op <- graphics::par(mar = c(0.5, 0.5, 2.2, 0.5))
  on.exit(graphics::par(op), add = TRUE)

  if (!is.null(context)) {
    ctx <- sf::st_geometry(sf::st_transform(context, sf::st_crs(x)))
    plot(ctx, col = "grey93", border = "grey60", lwd = 1.2, main = main, ...)
    plot(sf::st_geometry(x), col = fill, border = border, lwd = 0.6, add = TRUE)
  } else {
    plot(sf::st_geometry(x), col = fill, border = border, lwd = 0.6,
         main = main, ...)
  }

  lab <- unit_label(x, label)
  if (!is.null(lab)) {
    pts <- suppressWarnings(sf::st_coordinates(sf::st_point_on_surface(
      sf::st_geometry(x))))
    graphics::text(pts[, 1], pts[, 2], labels = lab, cex = 0.7, font = 2)
  }
  invisible(x)
}

# Label with the most specific thing the table actually carries.
unit_label <- function(x, label) {
  if (length(label) == 1L && is.na(label)) return(NULL)
  if (!is.null(label)) {
    if (!(label %in% names(x))) {
      stop("`label` names no column of `x`.", call. = FALSE)
    }
    return(as.character(x[[label]]))
  }
  if (nrow(x) > 60L) return(NULL)  # unreadable past that
  for (v in c("range_name", "inspectorate_name", "directorate_name", "compartment", "sheetID")) {
    if (v %in% names(x) && !all(is.na(x[[v]]))) return(as.character(x[[v]]))
  }
  NULL
}
