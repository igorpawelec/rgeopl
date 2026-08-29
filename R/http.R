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

# `path` streams the body straight to that file instead of assembling it in
# memory first, which is the difference between a point cloud tile costing
# nothing and costing its own size in RAM.
gp_perform <- function(req, what = "request", path = NULL) {
  out <- tryCatch(
    httr2::req_perform(req, path = path),
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

# Many files at once. The concurrency is in curl, not in R: the requests fly in
# parallel but every cache decision and every manifest write still happens on
# one thread, in order, which is what keeps the manifest honest.
#' @keywords internal
#' @noRd
gp_download_many <- function(urls, group, filenames = NULL,
                             labels = NA_character_, overwrite = FALSE,
                             n_active = NULL, quiet = FALSE) {
  n <- length(urls)
  filenames <- rep_len(filenames %||% list(NULL), n)
  labels <- rep_len(labels, n)
  out <- rep(NA_character_, n)

  if (!overwrite) out <- cache_lookup_many(urls)
  todo <- which(is.na(out))
  if (length(todo) == 0L) {
    say(quiet, "  all ", n, " already cached")
    return(out)
  }
  # One fetch per distinct file. A URL repeated in the same selection resolves
  # to the same target path, so fetching it twice would mean two transfers
  # racing to write one temporary file -- and the loser corrupting the winner.
  first <- todo[!duplicated(urls[todo])]
  if (length(first) < length(todo)) {
    say(quiet, "  ", length(todo), " rows point at ", length(first),
        " distinct files")
  }
  say(quiet, "  ", length(first), " to fetch, ", n - length(todo), " cached")

  targets <- lapply(first, function(i) cache_target(urls[i], group, filenames[[i]]))
  parts <- vapply(targets, function(t) paste0(t$abs, ".part"), character(1))
  on.exit(unlink(parts[file.exists(parts)]), add = TRUE)

  reqs <- lapply(urls[first], function(u) {
    gp_req(u, timeout = getOption("rgeopl.download_timeout", 900))
  })
  resps <- perform_many(reqs, paths = parts, n = n_active, quiet = quiet,
                        what = "downloads")
  ok <- split_responses(resps, quiet, "downloads")

  resolved <- stats::setNames(rep(NA_character_, length(first)), urls[first])
  kept <- logical(length(first))
  for (j in seq_along(first)) {
    if (!ok[j] || !file.exists(parts[j]) || file.size(parts[j]) == 0) {
      unlink(parts[j])
      next
    }
    file.rename(parts[j], targets[[j]]$abs)
    resolved[j] <- targets[[j]]$abs
    kept[j] <- TRUE
  }
  # The manifest is written once for the batch, after every file has landed.
  if (any(kept)) {
    cache_record_many(
      urls[first[kept]],
      vapply(targets[kept], function(t) t$rel, character(1)),
      group, labels[first[kept]]
    )
  }
  out[todo] <- unname(resolved[urls[todo]])
  out
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

  # Written straight to disk as it arrives, the same way the parallel path
  # does it. An error page lands in the file too, and is cleaned up on exit.
  resp <- gp_perform(req, "download", path = tmp)
  status <- httr2::resp_status(resp)
  if (status >= 400) {
    rlang::abort(
      c(paste0("Download failed with HTTP ", status, "."), i = paste0("URL: ", url)),
      class = "rgeopl_http_error"
    )
  }

  if (!file.exists(tmp) || file.size(tmp) == 0) {
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
