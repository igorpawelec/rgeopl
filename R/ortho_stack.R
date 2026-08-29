# Four-band orthophotos -------------------------------------------------------
#
# GUGiK publishes each orthophoto flight as two three-band products: RGB, and
# CIR as (NIR, red, green). Measured on one sheet, 2025, 0.25 m, the two agree
# to a correlation of 0.999 on red and on green -- they are the same
# radiometric product cut two ways, not two independent renderings. The
# infrared band correlates with nothing in RGB (0.19 to 0.47), which is what it
# should do.
#
# So combining them is not a merge of two pictures. It is adding the one band
# CIR lacks -- blue -- to the three it already has. That also means a vegetation
# index wants CIR alone: infrared and red come from one file, already
# consistent, and RGB adds nothing to that calculation.

#' Orthophoto as one four-band raster
#'
#' Joins the CIR and RGB products of the same flight into a single raster with
#' near-infrared, red, green and blue. Downloads what it needs, mosaics each
#' product, and stacks them.
#'
#' @param index An orthophoto index from [ortho_request()].
#' @param aoi The area to cut to, as in [tile_mosaic()].
#' @param crop,mask Passed to [tile_mosaic()]. `crop = "aoi"` cuts to the area,
#'   `mask = TRUE` also cuts to its outline.
#' @param bands `"nrgb"` for all four; `"cir"` for infrared, red and green
#'   alone, which halves the download and is all a vegetation index needs.
#' @param year,resolution Which flight to use. `NULL` picks the most recent
#'   vintage that publishes both products, at its finest pixel. See
#'   [ortho_pairs()] for what is on offer.
#' @param filename Write the result here.
#' @param overwrite,max_active,quiet Passed through to the download.
#'
#' @return A `terra::SpatRaster` whose layers are named `NIR`, `R`, `G` and `B`,
#'   or `NIR`, `R`, `G` with `bands = "cir"`.
#'
#' @section Why not an argument to `tile_mosaic()`:
#' [tile_mosaic()] refuses to join tiles of different band compositions, and
#' that refusal is the point: RGB and CIR laid side by side in one mosaic would
#' make band 1 mean two different things in two halves of the picture. Stacking
#' them is a different operation -- spectral rather than spatial -- so it gets
#' its own verb rather than a flag that switches the guard off.
#'
#' @examples
#' \dontrun{
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#' idx <- ortho_request(aoi)
#'
#' ortho_pairs(idx)                       # which vintages have both products
#'
#' nrgb <- ortho_stack(idx, aoi, mask = TRUE)
#' terra::plotRGB(nrgb, r = 1, g = 2, b = 3)   # false colour: vegetation red
#'
#' ndvi <- (nrgb[["NIR"]] - nrgb[["R"]]) / (nrgb[["NIR"]] + nrgb[["R"]])
#' }
#'
#' @seealso [ortho_pairs()], [tile_mosaic()].
#' @export
ortho_stack <- function(index, aoi = NULL, crop = c("aoi", "tiles"),
                        mask = FALSE, bands = c("nrgb", "cir"), year = NULL,
                        resolution = NULL, filename = NULL, overwrite = FALSE,
                        max_active = NULL, quiet = FALSE) {
  crop <- match.arg(crop)
  bands <- match.arg(bands)
  if (!requireNamespace("terra", quietly = TRUE)) {
    stop("Package 'terra' is needed to stack rasters. Install it first.",
         call. = FALSE)
  }
  if (!is.data.frame(index) || !("composition" %in% names(index))) {
    stop("`index` must be an orthophoto index from ortho_request().",
         call. = FALSE)
  }

  want <- if (bands == "nrgb") c("CIR", "RGB") else "CIR"
  choice <- pick_flight(index, want, year, resolution)
  say(quiet, "Using ", choice$year, ", ", choice$resolution, " m")

  parts <- lapply(want, function(comp) {
    sel <- flight_tiles(index, choice, comp)
    say(quiet, "  ", comp, ": ", nrow(sel), " tiles")
    tile_mosaic(sel, aoi = aoi, crop = crop, mask = mask,
                overwrite = overwrite, max_active = max_active, quiet = quiet)
  })
  names(parts) <- want

  if (bands == "cir") {
    out <- parts$CIR
    names(out) <- c("NIR", "R", "G")
  } else {
    check_same_grid(parts$CIR, parts$RGB, what = c("CIR", "RGB"))
    # CIR is (NIR, red, green) and its red and green are the same data as RGB's.
    # Blue is the only band RGB contributes.
    out <- c(parts$CIR[[1]], parts$RGB[[1]], parts$RGB[[2]], parts$RGB[[3]])
    names(out) <- c("NIR", "R", "G", "B")
  }

  if (!is.null(filename)) {
    say(quiet, "  writing ", basename(filename))
    out <- terra::writeRaster(out, filename, overwrite = TRUE)
  }
  out
}

#' Which orthophoto vintages publish both products
#'
#' The first question [ortho_stack()] raises: a four-band image needs a flight
#' whose CIR and RGB were both published, at the same pixel size.
#'
#' @param index An orthophoto index from [ortho_request()].
#'
#' @return A data frame of `year`, `resolution` and the tile count of each
#'   composition, newest first, keeping only the combinations that have both.
#'
#' @examples
#' \dontrun{
#' ortho_pairs(ortho_request(as_aoi(c(16.80, 52.44), buffer = 600)))
#' }
#'
#' @seealso [ortho_stack()]
#' @export
ortho_pairs <- function(index) {
  if (!is.data.frame(index) || !("composition" %in% names(index))) {
    stop("`index` must be an orthophoto index from ortho_request().",
         call. = FALSE)
  }
  d <- as.data.frame(index)
  tab <- table(paste(d$year, d$resolution), d$composition)
  # An index holding only one of the two has no column for the other, and
  # asking for it by name would error rather than answer "none".
  keep <- if (all(c("CIR", "RGB") %in% colnames(tab))) {
    rownames(tab)[tab[, "CIR"] > 0 & tab[, "RGB"] > 0]
  } else {
    character(0)
  }
  if (length(keep) == 0L) {
    return(data.frame(year = integer(0), resolution = numeric(0),
                      CIR = integer(0), RGB = integer(0)))
  }
  split_key <- do.call(rbind, strsplit(keep, " ", fixed = TRUE))
  out <- data.frame(
    year = as.integer(split_key[, 1]),
    resolution = as.numeric(split_key[, 2]),
    CIR = as.integer(tab[keep, "CIR"]),
    RGB = as.integer(tab[keep, "RGB"]),
    stringsAsFactors = FALSE
  )
  out[order(-out$year, out$resolution), , drop = FALSE]
}

# The newest flight that has everything asked for, at its finest pixel.
pick_flight <- function(index, want, year, resolution) {
  d <- as.data.frame(index)
  if (!is.null(year)) d <- d[d$year == year, , drop = FALSE]
  if (!is.null(resolution)) d <- d[d$resolution == resolution, , drop = FALSE]
  if (nrow(d) == 0L) {
    stop("No orthophoto tiles left after filtering on year or resolution.",
         call. = FALSE)
  }

  combos <- unique(d[, c("year", "resolution")])
  has_all <- vapply(seq_len(nrow(combos)), function(i) {
    rows <- d$year == combos$year[i] & d$resolution == combos$resolution[i]
    all(want %in% d$composition[rows])
  }, logical(1))

  if (!any(has_all)) {
    stop(
      "No vintage here publishes ", paste(want, collapse = " and "),
      " at one pixel size.\n  Available: ",
      paste(sprintf("%d (%s m): %s", d$year, d$resolution, d$composition)[
        !duplicated(paste(d$year, d$resolution, d$composition))][1:min(8, nrow(d))],
        collapse = "; "),
      call. = FALSE
    )
  }
  ok <- combos[has_all, , drop = FALSE]
  ok <- ok[order(-ok$year, ok$resolution), , drop = FALSE]
  list(year = ok$year[1], resolution = ok$resolution[1])
}

# One clean set of tiles for one product of one flight.
flight_tiles <- function(index, choice, composition) {
  one_per_sheet(index[index$year == choice$year &
                      index$resolution == choice$resolution &
                      index$composition == composition, , drop = FALSE])
}
