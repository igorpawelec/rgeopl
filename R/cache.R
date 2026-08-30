# On-disk cache -------------------------------------------------------------
#
# Two separate stores, because they have different lifetimes:
#
#   meta/   index responses (which tiles exist, and where). Small, JSON-ish,
#           and they do change when GUGiK publishes a new flight. Kept with a
#           time-to-live so a stale index expires on its own.
#   files/  the actual downloads: rasters, point clouds, archives. Large and
#           immutable once fetched, so they never expire. A manifest records
#           what came from where, which is what makes "do not download this
#           again" possible across sessions.

#' Cache location
#'
#' The cache lives in the directory given by `getOption("rgeopl.cache_dir")`,
#' falling back to a per-user cache directory. Set the option (in your
#' `.Rprofile`, or per session) to put it somewhere with room to spare, which
#' you will want as soon as you start pulling point clouds.
#'
#' @param create Create the directory if it does not exist.
#'
#' @return The cache root, invisibly for `cache_set_dir()`.
#'
#' @examples
#' \dontrun{
#' cache_set_dir("D:/geodata/cache")
#' cache_dir()
#' }
#'
#' @export
cache_dir <- function(create = TRUE) {
  root <- getOption("rgeopl.cache_dir", NULL)
  if (is.null(root)) root <- tools::R_user_dir("rgeopl", which = "cache")
  root <- path.expand(root)
  if (create) {
    for (d in c(root, file.path(root, "meta"), file.path(root, "files"))) {
      if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
  }
  root
}

#' @rdname cache_dir
#' @param path Directory to use as the cache root.
#' @export
cache_set_dir <- function(path) {
  options(rgeopl.cache_dir = path)
  invisible(cache_dir())
}

cache_key <- function(...) {
  rlang::hash(list(...))
}

# Index cache ---------------------------------------------------------------

meta_path <- function(key) file.path(cache_dir(), "meta", paste0(key, ".rds"))

meta_get <- function(key, ttl = index_ttl()) {
  if (isTRUE(getOption("rgeopl.cache_disable", FALSE))) return(NULL)
  f <- meta_path(key)
  if (!file.exists(f)) return(NULL)
  if (is.finite(ttl)) {
    age <- as.numeric(difftime(Sys.time(), file.mtime(f), units = "secs"))
    if (age > ttl) return(NULL)
  }
  tryCatch(readRDS(f), error = function(e) NULL)
}

meta_set <- function(key, value) {
  if (isTRUE(getOption("rgeopl.cache_disable", FALSE))) return(invisible(value))
  write_rds_atomic(value, meta_path(key))
  invisible(value)
}

index_ttl <- function() {
  as.numeric(getOption("rgeopl.index_ttl", 24 * 3600))
}

# File cache ----------------------------------------------------------------

manifest_path <- function() file.path(cache_dir(), "manifest.rds")

empty_manifest <- function() {
  data.frame(
    url = character(),
    path = character(),
    group = character(),
    label = character(),
    bytes = numeric(),
    downloaded = as.POSIXct(character()),
    stringsAsFactors = FALSE
  )
}

#' Inspect and prune the download cache
#'
#' @param group Restrict to one group (for example `"dem"`, `"ortho"`,
#'   `"pointcloud"`, `"bdl"`). `NULL` means all groups.
#' @param older_than Drop entries downloaded more than this many days ago.
#'   `NULL` means no age limit.
#' @param meta Also clear the cached index responses.
#' @param confirm Ask before deleting. Set to `FALSE` in scripts.
#'
#' @return `cache_info()` a data frame, one row per cached file, with a
#'   summary printed. `cache_clear()` returns the number of files removed,
#'   invisibly.
#'
#' @examples
#' \dontrun{
#' cache_info()
#' cache_clear(group = "ortho", older_than = 90, confirm = FALSE)
#' }
#'
#' @export
cache_info <- function(group = NULL) {
  m <- read_manifest()
  m <- validate_manifest(m)
  if (!is.null(group)) m <- m[m$group %in% group, , drop = FALSE]
  if (nrow(m) == 0L) {
    message("Cache is empty (", cache_dir(create = FALSE), ").")
    return(invisible(m))
  }
  by_group <- tapply(m$bytes, m$group, sum)
  message("Cache at ", cache_dir(create = FALSE), ": ",
          nrow(m), " files, ", format_bytes(sum(m$bytes)))
  for (g in names(by_group)) {
    message("  ", format(g, width = 12), " ",
            sum(m$group == g), " files, ", format_bytes(by_group[[g]]))
  }
  invisible(m)
}

#' @rdname cache_info
#' @export
cache_clear <- function(group = NULL, older_than = NULL, meta = FALSE,
                        confirm = interactive()) {
  m <- validate_manifest(read_manifest())
  drop <- rep(TRUE, nrow(m))
  if (!is.null(group)) drop <- drop & m$group %in% group
  if (!is.null(older_than)) {
    age <- as.numeric(difftime(Sys.time(), m$downloaded, units = "days"))
    drop <- drop & !is.na(age) & age > older_than
  }

  n <- sum(drop)
  if (n == 0L && !meta) {
    message("Nothing to remove.")
    return(invisible(0L))
  }
  if (confirm) {
    ans <- readline(paste0("Remove ", n, " cached files (",
                           format_bytes(sum(m$bytes[drop])), ")? [y/N] "))
    if (!tolower(trimws(ans)) %in% c("y", "yes")) {
      message("Cancelled.")
      return(invisible(0L))
    }
  }

  targets <- which(drop)
  paths <- file.path(cache_dir(), m$path[targets])
  removed <- suppressWarnings(file.remove(paths))

  # Forget only what is no longer on disk. A file that is still open refuses to
  # be removed on Windows -- a SpatRaster held in the session is enough -- and
  # dropping its row anyway would leave a file that the manifest does not know
  # about, cache_info() does not count, and nothing will ever clean up or
  # reuse. Rows whose file was already gone are forgotten either way.
  stayed <- file.exists(paths)
  keep <- rep(TRUE, nrow(m))
  keep[targets[!stayed]] <- FALSE
  write_manifest(m[keep, , drop = FALSE])

  if (any(stayed)) {
    rlang::warn(c(
      paste0(sum(stayed), " file", if (sum(stayed) == 1L) "" else "s",
             " could not be removed and ", if (sum(stayed) == 1L) "is" else "are",
             " still in the cache."),
      i = "Something still has them open; close it and clear again.",
      i = paste0("First: ", basename(paths[stayed][1]))
    ))
  }

  if (meta) {
    metas <- list.files(file.path(cache_dir(), "meta"), full.names = TRUE)
    file.remove(metas)
    message("Cleared ", length(metas), " cached index responses.")
  }
  message("Removed ", n_files(sum(removed)), ".")
  invisible(sum(removed))
}

read_manifest <- function() {
  f <- manifest_path()
  if (!file.exists(f)) return(empty_manifest())
  out <- tryCatch(readRDS(f), error = function(e) empty_manifest())
  if (!is.data.frame(out)) return(empty_manifest())
  out
}

write_manifest <- function(m) {
  write_rds_atomic(m, manifest_path())
  invisible(m)
}

# Drop rows whose file has gone missing, so a manually deleted file is simply
# re-downloaded instead of being reported as cached.
validate_manifest <- function(m) {
  if (nrow(m) == 0L) return(m)
  ok <- file.exists(file.path(cache_dir(), m$path))
  m[ok, , drop = FALSE]
}

# Where a given URL should land on disk.
cache_target <- function(url, group, filename = NULL) {
  filename <- filename %||% basename(sub("[?#].*$", "", url))
  if (!nzchar(filename)) filename <- paste0(cache_key(url), ".bin")
  filename <- with_url_extension(filename, url)
  # Keep the URL hash in the path: two flights can produce the same file name
  # for different years, and the name alone would collide.
  rel <- file.path("files", group, paste0(substr(cache_key(url), 1, 8), "_", filename))
  abs <- file.path(cache_dir(), rel)
  d <- dirname(abs)
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  list(rel = rel, abs = abs)
}

# The manifest is one file for the whole cache, so a batch of URLs reads it
# once. Asking per URL meant a download of a thousand tiles read the table a
# thousand times, and the table only ever grows: measured at 1.1 ms a lookup
# with 1500 rows in it, 4.2 ms at 10 000 and 22.8 ms at 50 000.
cache_lookup_many <- function(urls) {
  out <- rep(NA_character_, length(urls))
  m <- read_manifest()
  if (nrow(m) == 0L) return(out)

  # The newest row for a URL is the one that counts, and `match()` finds the
  # oldest, so the search runs backwards through the table.
  pos <- nrow(m) + 1L - match(urls, rev(m$url))
  found <- which(!is.na(pos))
  if (length(found) == 0L) return(out)

  abs <- file.path(cache_dir(), m$path[pos[found]])
  size <- file.size(abs)      # NA where the file is no longer there
  # A truncated download would otherwise be served forever.
  usable <- !is.na(size) & (is.na(m$bytes[pos[found]]) | size == m$bytes[pos[found]])
  out[found] <- ifelse(usable, abs, NA_character_)
  out
}

cache_lookup <- function(url) {
  hit <- cache_lookup_many(url)
  if (is.na(hit)) NULL else hit
}

# Likewise one write for the batch. Rewriting the whole table per file cost
# 6.6 ms each with 1500 rows in it and 71 ms at 50 000, all of it spent
# serialising rows that had not changed.
cache_record_many <- function(urls, rels, group, labels = NA_character_) {
  abs <- file.path(cache_dir(), rels)
  rows <- data.frame(
    url = urls, path = rels, group = group,
    label = rep_len(labels, length(urls)),
    bytes = file.size(abs), downloaded = Sys.time(),
    stringsAsFactors = FALSE
  )
  m <- read_manifest()
  m <- m[!(m$url %in% urls), , drop = FALSE]
  write_manifest(rbind(m, rows))
  invisible(abs)
}

cache_record <- function(url, rel, group, label = NA_character_) {
  cache_record_many(url, rel, group, label)
}

# Helpers -------------------------------------------------------------------

write_rds_atomic <- function(x, path) {
  tmp <- paste0(path, ".tmp", Sys.getpid())
  saveRDS(x, tmp)
  ok <- file.rename(tmp, path)
  if (!ok) {
    # file.rename refuses to overwrite on some Windows setups
    file.copy(tmp, path, overwrite = TRUE)
    unlink(tmp)
  }
  invisible(path)
}

n_files <- function(n) paste0(n, if (n == 1L) " file" else " files")

format_bytes <- function(x) {
  x <- sum(x, na.rm = TRUE)
  units <- c("B", "kB", "MB", "GB", "TB")
  i <- if (x <= 0) 1L else min(length(units), floor(log(x, 1024)) + 1L)
  paste0(format(round(x / 1024^(i - 1), 1), trim = TRUE), " ", units[i])
}

# The index names a point cloud tile 6017_642952_N-34-79-C-a-1-4-2, with no
# extension, while the URL it gives ends in .laz. Saved under the bare name
# the file is still a perfectly good LAZ -- it begins with LASF -- but lidR
# refuses it with "File not supported", because it decides by the name. So
# the extension the URL states is carried over, which also leaves the cache
# browsable by anything else. Orthophoto URLs carry no extension either and
# are untouched; those are recognised by their contents instead.
with_url_extension <- function(filename, url) {
  if (nzchar(tools::file_ext(filename))) return(filename)
  ext <- tools::file_ext(sub("[?#].*$", "", url))
  if (!nzchar(ext) || nchar(ext) > 5 || grepl("[^A-Za-z0-9]", ext)) return(filename)
  paste0(filename, ".", tolower(ext))
}
