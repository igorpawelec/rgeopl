# Package options

All options are read at call time, so setting them mid-session takes
effect immediately.

## Details

- \`rgeopl.cache_dir\`:

  Cache root. Defaults to a per-user cache directory; point it at a disk
  with room for point clouds.

- \`rgeopl.cache_disable\`:

  \`TRUE\` to bypass the index cache entirely.

- \`rgeopl.index_ttl\`:

  Seconds before a cached index response is considered stale. Default
  one day.

- \`rgeopl.timeout\`:

  Timeout in seconds for index queries, which should fail fast. Default
  120.

- \`rgeopl.download_timeout\`:

  Timeout in seconds for file downloads, which legitimately take
  minutes. Default 900.

- \`rgeopl.max_tries\`:

  Attempts per request, including the first. Default 3.

- \`rgeopl.max_active\`:

  How many requests to have in flight at once when a query is split
  across features, or when several files are downloaded together.
  Default 6, capped at 16.

- \`rgeopl.throttle\`:

  Requests per second, or \`NULL\` for no limit. Worth setting when
  walking a large index page by page.

- \`rgeopl.progress\`:

  \`FALSE\` to suppress progress bars everywhere. They are drawn only
  where there is more than one step and a terminal to draw on, so
  scripts and checks are unaffected either way.

- \`rgeopl.user_agent\`:

  User agent string sent with every request.
