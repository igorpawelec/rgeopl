# Shared by every test that needs a cache of its own: a fresh directory per
# test, thrown away afterwards, so nothing touches the user's real one.

local_cache <- function(env = parent.frame()) {
  dir <- file.path(tempdir(), paste0("rgeopl-test-", as.integer(runif(1, 1, 1e9))))
  withr::local_options(list(rgeopl.cache_dir = dir), .local_envir = env)
  withr::defer(unlink(dir, recursive = TRUE), envir = env)
  cache_dir()
}

# A file in the cache, of a stated size, returning its path relative to the
# cache root -- which is what the manifest stores.
put <- function(name, bytes = 10) {
  rel <- file.path("files", "dem", name)
  abs <- file.path(cache_dir(), rel)
  dir.create(dirname(abs), recursive = TRUE, showWarnings = FALSE)
  writeBin(as.raw(rep(1, bytes)), abs)
  rel
}
