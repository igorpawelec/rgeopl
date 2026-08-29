# Point cloud tiles, downloaded and identified

Fetches what an index points at, checks it is one survey, and returns
the files with the coordinate system the archive says they are in. The
pair to \[tile_mosaic()\]: that one ends the raster chain, this one ends
the point cloud chain, one step short of a \`lidR\` catalogue.

## Usage

``` r
pointcloud_get(
  index,
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

- allow_mixed:

  Accept more than one survey. Off by default: two flights over one
  place means returns from both in the same cloud, which inflates
  density, doubles the canopy surface and puts two ground levels under
  it.

- overwrite, max_active, quiet:

  Passed to \[tile_download()\].

## Value

The index, keeping only rows whose file arrived, with \`path\` (the
cached \`.laz\`) and \`epsg\` added.

## Reading them

\`lidR\` is the tool for what comes next, and it needs one thing the
files do not provide. Older surveys leave the projection record empty,
so the coordinate system has to come from the index:

“\` pc \<- pointcloud_get(subset(idx, year == 2024)) ctg \<-
lidR::readLAScatalog(pc\$path) sf::st_crs(ctg) \<- pc\$epsg\[1\] “\`

\`lidR\` is not on CRAN – it was archived on 2026-06-09 together with
\`rlas\` – but it is maintained and installable:

“\` install.packages("lidR", repos = "https://r-lidar.r-universe.dev")
“\`

## What it refuses, and why

The same discipline as \[tile_mosaic()\], for the same reason: a mixture
that produces a plausible-looking result nobody would question. More
than one vintage means overlapping returns from two flights; more than
one vertical datum means the ground sits at two heights in one
selection.

## See also

\[pointcloud_request()\] to find the tiles, \[chm_get()\] for a canopy
model built from the published elevation models instead.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(rgeopl_example("gleboczek_aoi.shp"))

idx <- pointcloud_request(aoi)
pc <- pointcloud_get(subset(idx, year == max(year)))

pc$path
pc$epsg[1]
} # }
```
