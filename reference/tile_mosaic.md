# Join downloaded tiles into one raster

Takes an index, downloads what it points at, and mosaics it. The pair to
\[tile_download()\]: that one fetches, this one joins.

## Usage

``` r
tile_mosaic(
  index,
  aoi = NULL,
  crop = c("aoi", "tiles"),
  mask = FALSE,
  filename = NULL,
  allow_mixed = FALSE,
  overwrite = FALSE,
  max_active = NULL,
  quiet = FALSE,
  gdal = NULL
)
```

## Arguments

- index:

  An index from \[ortho_request()\], \[dem_request()\] or
  \[pointcloud_request()\], filtered to what you want. It must describe
  one product, from one survey, in one coordinate system – see below.

- aoi:

  The area to cut to. Defaults to the index's own extent when \`crop =
  "tiles"\`.

- crop:

  \`"aoi"\` cuts the mosaic to the area of interest, \`"tiles"\` keeps
  the full extent of every tile that was fetched.

- mask:

  Also mask to the area's outline, not just its bounding box. Only
  meaningful with \`crop = "aoi"\` and a non-rectangular area.

- filename:

  Write the result here. \`NULL\` keeps it in memory or in terra's
  temporary space, which is fine for a few tiles and not for fifty.

- allow_mixed:

  Join tiles that disagree on vintage, product, band composition,
  resolution or datum. Off by default, and worth leaving off: every one
  of those produces a raster that looks finished and is not.

- overwrite:

  Passed to \[tile_download()\]: re-fetch tiles already cached.

- max_active:

  Passed to \[tile_download()\]: how many downloads to have in flight at
  once.

- quiet:

  Suppress progress.

- gdal:

  GDAL creation options for the written file, as a character vector.
  \`NULL\`, the default, writes DEFLATE with the predictor that suits
  the data, tiled, and BIGTIFF when the size calls for it. Pass your own
  to replace that wholesale – for a Cloud Optimized GeoTIFF, say, or to
  turn compression off.

## Value

A \`terra::SpatRaster\`.

## What it refuses, and why

- More than one vintage:

  Orthophotos from different flights differ in sun angle, phenology and
  radiometry; the join shows as a visible seam, and the two halves are
  months or years apart in what they depict.

- More than one product:

  A terrain model and a surface model are different quantities.
  Mosaicking them makes a surface that is neither.

- More than one composition:

  RGB and false-colour infrared are both three bands, so they join
  without complaint, and band 1 then means two different things in two
  halves of the picture.

- More than one resolution:

  One of them gets resampled, silently.

- More than one vertical datum:

  PL-KRON86-NH and PL-EVRF2007-NH differ by tens of centimetres. The
  seam is a step in the terrain that is not there.

- More than one file format:

  Every elevation sheet is published both as a grid and as a list of
  points, under the same sheet number. The point list is not a raster,
  so half such a mosaic would simply be missing.

- Point clouds:

  LAS and LAZ are not rasters. Use \`lidR\` or \`PDAL\`.

## See also

\[tile_download()\] to fetch without joining.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
idx <- ortho_request(aoi)

recent <- subset(idx, year == max(year) & composition == "RGB")
picture <- tile_mosaic(recent, aoi, crop = "aoi", mask = TRUE)
terra::plotRGB(picture)
} # }
```
