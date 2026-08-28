#' @keywords internal
"_PACKAGE"

.onLoad <- function(libname, pkgname) {
  defaults <- list(
    rgeopl.timeout = 120,
    rgeopl.download_timeout = 900,
    rgeopl.max_tries = 3L,
    rgeopl.index_ttl = 24 * 3600
  )
  unset <- !(names(defaults) %in% names(options()))
  if (any(unset)) options(defaults[unset])
  invisible()
}
