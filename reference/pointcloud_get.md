# Point cloud tiles as a catalogue ready for lidR

Downloads what an index points at and returns it as a
\`lidR::LAScatalog\`, with the coordinate system attached. The pair to
\[tile_mosaic()\]: that one ends the raster chain, this one ends the
point cloud chain.

## Usage

``` r
pointcloud_get(
  index,
  filter = NULL,
  select = NULL,
  allow_mixed = FALSE,
  overwrite = FALSE,
  max_active = NULL,
  quiet = FALSE
)
```

## Arguments

- index:

  A point cloud index from \[pointcloud_request()\], filtered to what
  you want. It must describe one survey – see below.

- filter, select:

  Passed to \`lidR::readLAScatalog()\`, and worth setting here rather
  than later: both are applied as the points are read, so \`filter =
  "-drop_class 7"\` never loads the noise class at all. See
  \`lidR::readLAS()\` for the vocabulary.

- allow_mixed:

  Build a catalogue from more than one survey. Off by default: two
  flights over one place means returns from both in the same cloud,
  which inflates density, doubles the canopy surface and puts two ground
  levels under it.

- overwrite, max_active, quiet:

  Passed to \[tile_download()\].

## Value

A \`lidR::LAScatalog\`.

## Details

Everything after this is \`lidR\`'s: \`lidR::clip_roi()\` to cut to a
stand, \`lidR::rasterize_canopy()\` for a canopy model at the density
the cloud actually supports, \`lidR::normalize_height()\`,
\`lidR::segment_trees()\`.

## Getting lidR

\`lidR\` is not on CRAN. It was archived on 2026-06-09 along with
\`rlas\`, the package it reads LAS and LAZ files through, after
sanitiser reports went uncorrected. Both are still developed at
\<https://github.com/r-lidar\> and install from source:

“\` remotes::install_github("r-lidar/rlas")
remotes::install_github("r-lidar/lidR") “\`

Nothing else in this package needs it, and \[tile_download()\] will
fetch the same files for any other reader.

## What it refuses, and why

The same discipline as \[tile_mosaic()\], for the same reason: a mixture
that produces a plausible-looking result nobody would question. More
than one vintage means overlapping returns from two flights; more than
one vertical datum means the ground sits at two heights in one file.
Both come back as a catalogue that reads perfectly and describes nothing
real.

## See also

\[pointcloud_request()\] to find the tiles, \[chm_get()\] for a canopy
model built from the published elevation models instead.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))

idx <- pointcloud_request(aoi)
recent <- subset(idx, year == max(year))

ctg <- pointcloud_get(recent, filter = "-drop_class 7")
lidR::plot(ctg)

# a canopy model at the density the cloud supports, rather than the 1 m
# the coverage services publish
chm <- lidR::rasterize_canopy(ctg, res = 0.5, algorithm = lidR::p2r())
} # }
```
