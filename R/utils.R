`%||%` <- function(a, b) if (is.null(a)) b else a

drop_null <- function(x) x[!vapply(x, is.null, logical(1))]

# Split a vector into chunks of at most `size`. Used to turn a list of tens of
# thousands of object IDs into requests the server will actually accept.
chunk <- function(x, size) {
  if (length(x) == 0L) return(list())
  split(x, ceiling(seq_along(x) / size))
}

# Both services filter by bounding box only. For an area of interest that is
# not a rectangle -- which is most real ones -- that returns features beside
# the area as well as inside it. Keep whole features that touch the area:
# clipping their geometry would falsify the recorded areas.
keep_touching_aoi <- function(x, aoi) {
  if (nrow(x) == 0L) return(x)
  g <- aoi_geom(aoi, crs = sf::st_crs(x))
  hit <- lengths(sf::st_intersects(sf::st_geometry(x), sf::st_union(g))) > 0L
  x[hit, , drop = FALSE]
}

# Hand the object to whatever print method it would have had without our
# class. NextMethod() cannot be used here: the object may have lost its sf or
# tibble class along the way (st_drop_geometry keeps ours but drops theirs),
# and print.data.frame would then receive arguments it does not accept.
print_without_class <- function(x, cls, ...) {
  class(x) <- setdiff(class(x), cls)
  print(x, ...)
}

#' Package options
#'
#' All options are read at call time, so setting them mid-session takes effect
#' immediately.
#'
#' \describe{
#'   \item{`rgeopl.cache_dir`}{Cache root. Defaults to a per-user cache
#'     directory; point it at a disk with room for point clouds.}
#'   \item{`rgeopl.cache_disable`}{`TRUE` to bypass the index cache entirely.}
#'   \item{`rgeopl.index_ttl`}{Seconds before a cached index response is
#'     considered stale. Default one day.}
#'   \item{`rgeopl.timeout`}{Timeout in seconds for index queries, which
#'     should fail fast. Default 120.}
#'   \item{`rgeopl.download_timeout`}{Timeout in seconds for file downloads,
#'     which legitimately take minutes. Default 900.}
#'   \item{`rgeopl.max_tries`}{Attempts per request, including the first.
#'     Default 3.}
#'   \item{`rgeopl.max_active`}{How many requests to have in flight at once
#'     when a query is split across features, or when several files are
#'     downloaded together. Default 6, capped at 16.}
#'   \item{`rgeopl.throttle`}{Requests per second, or `NULL` for no limit.
#'     Worth setting when walking a large index page by page.}
#'   \item{`rgeopl.progress`}{`FALSE` to suppress progress bars everywhere.
#'     They are drawn only where there is more than one step and a terminal to
#'     draw on, so scripts and checks are unaffected either way.}
#'   \item{`rgeopl.user_agent`}{User agent string sent with every request.}
#' }
#'
#' @name rgeopl-options
NULL
