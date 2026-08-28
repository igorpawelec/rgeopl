# Progress reporting ---------------------------------------------------------
#
# Three different waits, so three different bars, and never two at once: a
# byte-level bar inside a file-level bar reads as flicker rather than as
# information.
#
#   index assembly      one step per request        (20 requests, ~80 s)
#   multi-file download one step per file           (tens of tiles, minutes)
#   single large file   bytes, from httr2           (a point cloud can be 200 MB)
#
# Everything here is a no-op when `quiet = TRUE` or when the user has set
# `options(rgeopl.progress = FALSE)`, and cli itself stays silent when there is
# no terminal to draw on, so scripts and `R CMD check` are unaffected.

progress_on <- function(quiet) {
  !isTRUE(quiet) && isTRUE(getOption("rgeopl.progress", TRUE))
}

pb_new <- function(total, format, quiet = FALSE, env = parent.frame()) {
  if (!progress_on(quiet) || is.na(total) || total <= 1L) return(NULL)
  cli::cli_progress_bar(format = format, total = total, clear = FALSE,
                        .envir = env)
}

pb_tick <- function(id, ...) {
  if (is.null(id)) return(invisible(NULL))
  cli::cli_progress_update(id = id, ...)
  invisible(NULL)
}

pb_done <- function(id) {
  if (is.null(id)) return(invisible(NULL))
  cli::cli_progress_done(id = id)
  invisible(NULL)
}

# Used where a bar would be wrong -- a single step, or a suppressed run -- but
# something should still be said.
say <- function(quiet, ...) {
  if (!isTRUE(quiet)) message(...)
  invisible(NULL)
}
