# HTTP layer ----------------------------------------------------------------
#
# One place where retries, timeouts, the user agent and error handling live,
# so that no client has to think about them. Two rules it enforces:
#
#   1. A failure raises a classed condition. It does not return the string
#      "connection error" and let the caller carry on with a broken object.
#   2. Long queries go out as POST. The ArcGIS index is addressed by lists of
#      object IDs, which run past any sane URL length limit.

gp_user_agent <- function() {
  getOption(
    "rgeopl.user_agent",
    paste0("rgeopl/", utils::packageVersion("rgeopl"),
           " (R package; +https://github.com/)")
  )
}

gp_req <- function(url, params = list(), method = c("GET", "POST"),
                   timeout = getOption("rgeopl.timeout", 120)) {
  method <- match.arg(method)

  req <- httr2::request(url)
  req <- httr2::req_user_agent(req, gp_user_agent())
  req <- httr2::req_timeout(req, timeout)
  req <- httr2::req_retry(
    req,
    max_tries = getOption("rgeopl.max_tries", 3L),
    retry_on_failure = TRUE
  )

  throttle <- getOption("rgeopl.throttle", NULL)
  if (!is.null(throttle)) req <- httr2::req_throttle(req, rate = throttle)

  if (length(params)) {
    params <- drop_null(params)
    req <- if (method == "GET") {
      httr2::req_url_query(req, !!!params)
    } else {
      httr2::req_body_form(req, !!!params)
    }
  }
  req
}

gp_perform <- function(req, what = "request") {
  out <- tryCatch(
    httr2::req_perform(req),
    error = function(e) e
  )
  if (inherits(out, "error")) {
    rlang::abort(
      c(
        paste0("The ", what, " failed."),
        i = conditionMessage(out),
        i = paste0("URL: ", req$url),
        i = if (grepl("geoportal|gugik", req$url)) {
          paste0("The GUGiK services are not reachable from outside Poland; ",
                 "a VPN endpoint in Poland is needed.")
        } else NULL
      ),
      class = "rgeopl_http_error"
    )
  }
  out
}

#' @keywords internal
#' @noRd
gp_json <- function(url, params = list(), method = "GET",
                    cache = TRUE, ttl = index_ttl()) {
  key <- cache_key("json", url, params, method)
  if (cache) {
    hit <- meta_get(key, ttl)
    if (!is.null(hit)) return(hit)
  }

  resp <- gp_perform(gp_req(url, params, method), "index query")
  txt <- httr2::resp_body_string(resp)
  out <- jsonlite::fromJSON(txt, simplifyVector = TRUE)

  # ArcGIS answers with HTTP 200 and an error object in the body.
  if (!is.null(out$error)) {
    rlang::abort(
      c(
        "The server rejected the query.",
        i = paste0("code ", out$error$code, ": ", out$error$message),
        i = paste0("URL: ", url)
      ),
      class = "rgeopl_service_error"
    )
  }

  if (cache) meta_set(key, out)
  out
}

#' @keywords internal
#' @noRd
gp_text <- function(url, params = list(), method = "GET",
                    cache = TRUE, ttl = index_ttl()) {
  key <- cache_key("text", url, params, method)
  if (cache) {
    hit <- meta_get(key, ttl)
    if (!is.null(hit)) return(hit)
  }
  resp <- gp_perform(gp_req(url, params, method), "index query")
  out <- httr2::resp_body_string(resp)

  # A service error still arrives as HTTP 200 with a JSON body.
  if (startsWith(trimws(out), "{") && grepl('"error"', substr(out, 1, 200))) {
    parsed <- tryCatch(jsonlite::fromJSON(out), error = function(e) NULL)
    if (!is.null(parsed$error)) {
      rlang::abort(
        c("The server rejected the query.",
          i = paste0("code ", parsed$error$code, ": ", parsed$error$message),
          i = paste0("URL: ", url)),
        class = "rgeopl_service_error"
      )
    }
  }

  if (cache) meta_set(key, out)
  out
}

#' @keywords internal
#' @noRd
gp_xml <- function(url, params = list(), cache = TRUE, ttl = index_ttl()) {
  key <- cache_key("xml", url, params)
  if (cache) {
    hit <- meta_get(key, ttl)
    if (!is.null(hit)) return(xml2::read_xml(hit))
  }
  resp <- gp_perform(gp_req(url, params), "index query")
  txt <- httr2::resp_body_string(resp)
  if (cache) meta_set(key, txt)
  xml2::read_xml(txt)
}

#' @keywords internal
#' @noRd
gp_download <- function(url, group, filename = NULL, label = NA_character_,
                        overwrite = FALSE, quiet = FALSE) {
  if (!overwrite) {
    hit <- cache_lookup(url)
    if (!is.null(hit)) {
      if (!quiet) message("  cached: ", basename(hit))
      return(hit)
    }
  }

  target <- cache_target(url, group, filename)
  tmp <- paste0(target$abs, ".part")
  on.exit(unlink(tmp), add = TRUE)

  # Downloads get their own, longer patience. An index query that stalls should
  # fail fast, but a raster legitimately takes minutes: the surface model comes
  # as an ASCII grid, and 1400 x 1400 pixels of it did not finish inside the
  # 120 s that is right for a query.
  req <- httr2::req_error(
    gp_req(url, timeout = getOption("rgeopl.download_timeout", 900)),
    is_error = function(resp) FALSE
  )

  # Byte-level progress for the single large file. A point cloud tile can run
  # to hundreds of megabytes, and without this the console goes quiet for
  # minutes with no way to tell work from a hang. Where the server sends no
  # Content-Length -- the coverage services do not -- httr2 falls back to a
  # spinner, which still answers the only question being asked.
  if (progress_on(quiet)) req <- httr2::req_progress(req)

  resp <- gp_perform(req, "download")
  status <- httr2::resp_status(resp)
  if (status >= 400) {
    rlang::abort(
      c(paste0("Download failed with HTTP ", status, "."), i = paste0("URL: ", url)),
      class = "rgeopl_http_error"
    )
  }

  writeBin(httr2::resp_body_raw(resp), tmp)
  if (file.size(tmp) == 0) {
    rlang::abort(
      c("The server returned an empty file.", i = paste0("URL: ", url)),
      class = "rgeopl_http_error"
    )
  }
  file.rename(tmp, target$abs)
  cache_record(url, target$rel, group, label)

  if (!quiet) {
    message("  saved: ", basename(target$abs), " (",
            format_bytes(file.size(target$abs)), ")")
  }
  target$abs
}
