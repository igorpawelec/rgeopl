local_cache <- function(env = parent.frame()) {
  dir <- file.path(tempdir(), paste0("rgeopl-test-", as.integer(runif(1, 1, 1e9))))
  withr::local_options(list(rgeopl.cache_dir = dir), .local_envir = env)
  withr::defer(unlink(dir, recursive = TRUE), envir = env)
  cache_dir()
}

test_that("the cache root is created with both stores", {
  root <- local_cache()
  expect_true(dir.exists(file.path(root, "meta")))
  expect_true(dir.exists(file.path(root, "files")))
})

test_that("index responses round-trip and expire", {
  local_cache()
  key <- cache_key("test", list(a = 1))
  expect_null(meta_get(key))

  meta_set(key, list(value = 42))
  expect_equal(meta_get(key)$value, 42)

  # a zero-second time-to-live makes anything already written stale
  expect_null(meta_get(key, ttl = -1))
})

test_that("the index cache can be switched off", {
  local_cache()
  withr::local_options(list(rgeopl.cache_disable = TRUE))
  key <- cache_key("test")
  meta_set(key, "value")
  expect_null(meta_get(key))
})

test_that("cache targets keep colliding file names apart", {
  local_cache()
  a <- cache_target("https://example.org/2019/tile.tif", "dem")
  b <- cache_target("https://example.org/2024/tile.tif", "dem")
  expect_true(dir.exists(dirname(a$abs)))
  expect_false(basename(a$abs) == basename(b$abs))
  expect_true(grepl("tile\\.tif$", basename(a$abs)))
})

test_that("a recorded file is found again, a truncated one is not", {
  local_cache()
  url <- "https://example.org/tile.tif"
  target <- cache_target(url, "dem")
  writeBin(as.raw(rep(1, 100)), target$abs)
  cache_record(url, target$rel, "dem", label = "test tile")

  expect_equal(normalizePath(cache_lookup(url)), normalizePath(target$abs))

  # a short file means the download was cut off: do not serve it
  writeBin(as.raw(rep(1, 50)), target$abs)
  expect_null(cache_lookup(url))
})

test_that("a manually deleted file drops out of the manifest view", {
  local_cache()
  url <- "https://example.org/tile.tif"
  target <- cache_target(url, "dem")
  writeBin(as.raw(rep(1, 100)), target$abs)
  cache_record(url, target$rel, "dem")

  expect_equal(nrow(validate_manifest(read_manifest())), 1L)
  unlink(target$abs)
  expect_equal(nrow(validate_manifest(read_manifest())), 0L)
  expect_null(cache_lookup(url))
})

test_that("recording the same url twice does not duplicate the row", {
  local_cache()
  url <- "https://example.org/tile.tif"
  target <- cache_target(url, "dem")
  writeBin(as.raw(rep(1, 100)), target$abs)
  cache_record(url, target$rel, "dem")
  cache_record(url, target$rel, "dem")
  expect_equal(nrow(read_manifest()), 1L)
})

test_that("cache_clear removes by group and by age", {
  local_cache()
  make <- function(url, group) {
    t <- cache_target(url, group)
    writeBin(as.raw(rep(1, 100)), t$abs)
    cache_record(url, t$rel, group)
  }
  make("https://example.org/a.tif", "dem")
  make("https://example.org/b.tif", "ortho")

  expect_equal(cache_clear(group = "dem", confirm = FALSE), 1L)
  expect_equal(nrow(validate_manifest(read_manifest())), 1L)

  # nothing is old enough yet
  expect_equal(cache_clear(older_than = 1, confirm = FALSE), 0L)
  expect_equal(nrow(validate_manifest(read_manifest())), 1L)
})

test_that("byte counts are formatted for humans", {
  expect_equal(format_bytes(0), "0 B")
  expect_equal(format_bytes(1024), "1 kB")
  expect_equal(format_bytes(1024^2 * 1.5), "1.5 MB")
  expect_equal(format_bytes(1024^3 * 4), "4 GB")
})
