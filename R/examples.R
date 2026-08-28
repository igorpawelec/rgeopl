#' Example areas of interest shipped with the package
#'
#' Two small vector files from real work in Polish forests, so that the
#' examples in this package point at somewhere data actually exists rather
#' than at made-up coordinates.
#'
#' \describe{
#'   \item{`test_lasow.shp`}{A single point in a Scots pine stand in the
#'     Wipsowo forest inspectorate (Olsztyn regional directorate), Warmia. Useful
#'     for asking what exists at one spot: seven elevation vintages, but only
#'     one airborne laser scan.}
#'   \item{`gleboczek_aoi.shp`}{Two polygons, about 600 ha together, near
#'     Gniezno in Wielkopolska. A realistic survey area: multi-feature,
#'     detailed boundaries, and large enough that the index runs to several
#'     pages.}
#' }
#'
#' Both are in EPSG:2180 (PL-1992).
#'
#' @param name File name, for example `"test_lasow.shp"`. Omit to list what
#'   is available.
#'
#' @return The path to the file, or a character vector of available names.
#'
#' @examples
#' rgeopl_example()
#'
#' aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
#' aoi
#'
#' @export
rgeopl_example <- function(name = NULL) {
  dir <- system.file("extdata", package = "rgeopl")
  if (is.null(name)) {
    return(list.files(dir, pattern = "\\.shp$"))
  }
  path <- file.path(dir, name)
  if (!file.exists(path)) {
    stop("No example called `", name, "`. Available: ",
         paste(rgeopl_example(), collapse = ", "), call. = FALSE)
  }
  path
}
