#' Summarise and draw index coverage by vintage
#'
#' `coverage()` answers the question an index alone does not: for each vintage,
#' how much of the area is actually covered? That is what decides whether a
#' year can be mosaicked into one surface or only patches part of the area.
#'
#' `plot_coverage()` draws the same thing, in the manner of the Geoportal's own
#' coverage view: tiles filled by vintage, oldest first, so the most recent
#' data sits on top.
#'
#' @param index An index from [dem_request()], [ortho_request()] or
#'   [pointcloud_request()].
#' @param by Column to group and colour by. `"year"` by default; `"product"`,
#'   `"format"` and `"VRS"` are also useful.
#' @param aoi The area of interest the index was built from. When given,
#'   `coverage()` adds `aoi_share`: the fraction of the area covered by that
#'   group, which is the number to check before mosaicking.
#'
#' @return `coverage()` a data frame with one row per group: the grouping
#'   value, `tiles`, `area_km2` (area of the union of those tiles) and, when
#'   `aoi` is given, `aoi_share`. `plot_coverage()` returns `index` invisibly.
#'
#' @section What coverage does not tell you:
#' These are the outlines of map sheets, not of the imagery inside them. A
#' sheet that exists but is only partly filled still counts as covering its
#' whole footprint, so `aoi_share` can read 1 while the data has holes. The
#' index says which sheets those are, in `isFilled`; [tile_mosaic()] refuses a
#' selection that holds the same sheet twice, which is how the two versions
#' usually turn up.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#' idx <- ortho_request(aoi)
#'
#' coverage(idx, aoi = aoi)     # which vintages cover the whole area?
#' plot_coverage(idx, aoi = aoi)
#' }
#'
#' @export
coverage <- function(index, by = "year", aoi = NULL) {
  check_index_column(index, by)
  if (nrow(index) == 0L) {
    return(data.frame(tiles = integer(0), area_km2 = numeric(0)))
  }

  groups <- split(seq_len(nrow(index)), index[[by]], drop = TRUE)

  aoi_area <- NULL
  if (!is.null(aoi)) {
    aoi_geom_2180 <- sf::st_union(aoi_geom(as_aoi(aoi), crs = CRS_PL1992))
    aoi_area <- as.numeric(sum(sf::st_area(aoi_geom_2180)))
  }

  rows <- lapply(names(groups), function(g) {
    idx <- groups[[g]]
    u <- sf::st_union(sf::st_geometry(index[idx, ]))
    out <- data.frame(
      group = g,
      tiles = length(idx),
      area_km2 = round(as.numeric(sum(sf::st_area(u))) / 1e6, 2),
      stringsAsFactors = FALSE
    )
    if (!is.null(aoi_area)) {
      inter <- suppressWarnings(sf::st_intersection(u, aoi_geom_2180))
      covered <- if (length(inter) == 0L) 0 else as.numeric(sum(sf::st_area(inter)))
      out$aoi_share <- round(covered / aoi_area, 3)
    }
    out
  })

  out <- do.call(rbind, rows)
  names(out)[1] <- by
  out <- restore_type(out, by, index[[by]])
  out[order(out[[by]]), , drop = FALSE]
}

#' @rdname coverage
#' @param facet Draw one small panel per group. This is the default and the
#'   useful one: vintages overlap almost completely, so a single overlaid map
#'   shows the newest year and hides every other, which is the opposite of what
#'   is needed to choose between them. `FALSE` gives the overlaid map, newest
#'   on top, in the manner of the Geoportal's own view.
#' @param max_panels Cap on the number of panels. Excess groups are dropped,
#'   oldest first, with a message. Ignored when `facet = FALSE`.
#' @param palette A colour palette function taking `n`, or a vector of colours
#'   with one entry per group. Defaults to a sequential ramp, so newer vintages
#'   read as darker.
#' @param legend Draw a legend. Overlaid plots only.
#' @param main Plot title. `NULL` builds one from the index.
#' @param ... Passed to [graphics::plot()].
#' @export
plot_coverage <- function(index, by = "year", aoi = NULL, facet = TRUE,
                          max_panels = 24L, palette = NULL, legend = TRUE,
                          main = NULL, ...) {
  check_index_column(index, by)
  if (nrow(index) == 0L) {
    stop("The index has no rows: nothing to draw.", call. = FALSE)
  }

  values <- index[[by]]
  levels_ <- sort(unique(values))
  n <- length(levels_)

  cols <- coverage_palette(palette, n)

  if (is.null(main)) {
    what <- attr(index, "rgeopl_what") %||% "index"
    main <- paste0(what, " coverage by ", by)
  }

  if (!facet || n == 1L) {
    plot_coverage_overlay(index, values, levels_, cols, aoi, legend, main, ...)
  } else {
    plot_coverage_facets(index, by, values, levels_, cols, aoi, main,
                         max_panels, ...)
  }
  invisible(index)
}

coverage_palette <- function(palette, n) {
  if (is.null(palette)) {
    grDevices::hcl.colors(max(n, 2L), "YlGnBu", rev = TRUE)[seq_len(n)]
  } else if (is.function(palette)) {
    palette(n)
  } else {
    rep_len(palette, n)
  }
}

plot_coverage_overlay <- function(index, values, levels_, cols, aoi, legend,
                                  main, ...) {
  # Oldest first, so the newest vintage ends up on top.
  ord <- order(match(values, levels_))
  fill <- cols[match(values[ord], levels_)]

  op <- graphics::par(mar = c(2, 2, 3, if (legend) 7 else 2))
  on.exit(graphics::par(op), add = TRUE)

  plot(sf::st_geometry(index)[ord], col = fill, border = NA, main = main, ...)
  if (!is.null(aoi)) {
    plot(aoi_geom(as_aoi(aoi), crs = sf::st_crs(index)),
         add = TRUE, border = "black", lwd = 2, col = NA)
  }
  if (legend) {
    graphics::par(xpd = NA)
    usr <- graphics::par("usr")
    graphics::legend(
      x = usr[2] + diff(usr[1:2]) * 0.02, y = usr[4],
      legend = rev(as.character(levels_)), fill = rev(cols),
      bty = "n", cex = 0.8, title = NULL
    )
  }
}

plot_coverage_facets <- function(index, by, values, levels_, cols, aoi, main,
                                 max_panels, ...) {
  if (length(levels_) > max_panels) {
    dropped <- length(levels_) - max_panels
    message("Showing the ", max_panels, " most recent groups; ", dropped,
            " older ones not drawn (raise max_panels to see them).")
    levels_ <- utils::tail(levels_, max_panels)
    cols <- utils::tail(cols, max_panels)
  }

  shares <- NULL
  if (!is.null(aoi)) {
    cv <- coverage(index, by = by, aoi = aoi)
    shares <- stats::setNames(cv$aoi_share, as.character(cv[[by]]))
  }

  # One frame for every panel, so panels are comparable at a glance.
  frame <- sf::st_bbox(if (is.null(aoi)) sf::st_geometry(index) else
    sf::st_union(sf::st_geometry(index),
                 aoi_geom(as_aoi(aoi), crs = sf::st_crs(index))))
  xlim <- c(frame[["xmin"]], frame[["xmax"]])
  ylim <- c(frame[["ymin"]], frame[["ymax"]])

  n <- length(levels_)
  dims <- grDevices::n2mfrow(n, asp = diff(xlim) / diff(ylim))
  op <- graphics::par(mfrow = dims, mar = c(0.4, 0.4, 1.8, 0.4),
                      oma = c(0, 0, 2.4, 0))
  on.exit(graphics::par(op), add = TRUE)

  aoi_g <- if (is.null(aoi)) NULL else aoi_geom(as_aoi(aoi), crs = sf::st_crs(index))

  for (i in seq_along(levels_)) {
    lev <- levels_[i]
    sub <- sf::st_geometry(index)[values == lev]
    label <- as.character(lev)
    if (!is.null(shares) && !is.na(shares[label])) {
      label <- paste0(label, "  (", format(round(shares[label] * 100), trim = TRUE), "%)")
    }
    plot(sub, col = cols[i], border = NA, xlim = xlim, ylim = ylim,
         main = label, cex.main = 1, reset = FALSE, ...)
    if (!is.null(aoi_g)) {
      plot(aoi_g, add = TRUE, border = "black", lwd = 1.4, col = NA)
    }
    graphics::box(col = "grey80")
  }
  graphics::mtext(main, outer = TRUE, cex = 1.1, font = 2)
}

check_index_column <- function(index, by) {
  if (!is.data.frame(index)) {
    stop("`index` must be a data frame from one of the *_request() functions.",
         call. = FALSE)
  }
  if (length(by) != 1L || is.null(index[[by]])) {
    stop("`by` must name one column of `index`; `", by, "` is not there.",
         call. = FALSE)
  }
  invisible(TRUE)
}

# split() stringifies group names; put the original type back.
restore_type <- function(out, by, original) {
  if (is.factor(original)) {
    out[[by]] <- factor(out[[by]], levels = levels(original))
  } else if (is.integer(original)) {
    out[[by]] <- as.integer(out[[by]])
  } else if (is.numeric(original)) {
    out[[by]] <- as.numeric(out[[by]])
  }
  out
}
