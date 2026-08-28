# Download the tiles an index points to

Takes an index (or any filtered subset of one – a \`dplyr\` pipeline is
fine, the class does not have to survive) and fetches every row. Files
land in the cache, so a tile already on disk is not fetched twice,
across sessions.

## Usage

``` r
tile_download(
  index,
  outdir = NULL,
  unzip = TRUE,
  overwrite = FALSE,
  max_active = NULL,
  quiet = FALSE
)
```

## Arguments

- index:

  An index from \[dem_request()\], \[ortho_request()\] or
  \[pointcloud_request()\], or any data frame carrying \`URL\` and
  \`filename\` columns.

- outdir:

  Optional directory to copy the usable files into. The cache remains
  the store; this is an export, not a move.

- unzip:

  Extract downloaded archives. The archive itself stays in the cache, so
  the cache record stays valid.

- overwrite:

  Re-download even when the file is already cached.

- max_active:

  How many downloads to have in flight at once. Defaults to
  \`getOption("rgeopl.max_active", 6)\`. Downloads are limited by
  throughput rather than latency, so the gain is modest – measured at
  1.6x going from one connection to six – and these are public services,
  so the cap is deliberate.

- quiet:

  Suppress per-file messages.

## Value

The input with two columns added: \`path\` (the cached file, \`NA\` if
that one failed) and \`extracted\` (the directory an archive was
unpacked into, or \`NA\`). One tile failing does not abandon the rest.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(sf::st_read(rgeopl_example("test_lasow.shp"), quiet = TRUE), buffer = 500)
idx <- dem_request(aoi)
got <- tile_download(subset(idx, year == max(year) & format == "LAZ"))
got$path
} # }
```
