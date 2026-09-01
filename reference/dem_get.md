# Download an elevation model or an orthophoto for an area

Fetches the current model over an area of interest as a single raster,
ready to open. No tiles, no mosaicking, no vintage to choose: the
coverage service hands back exactly the extent you ask for.

## Usage

``` r
dem_get(
  aoi,
  product = c("dtm", "dsm"),
  resolution = 1,
  datum = c("evrf2007", "kron86"),
  filename = NULL,
  convert = TRUE,
  mask = FALSE,
  max_pixels = 2500,
  quiet = FALSE,
  gdal = NULL,
  file = NULL
)

ortho_get(
  aoi,
  product = c("standard", "high", "true"),
  resolution = 0.25,
  filename = NULL,
  convert = TRUE,
  mask = FALSE,
  max_pixels = 2500,
  quiet = FALSE,
  gdal = NULL,
  file = NULL
)
```

## Arguments

- aoi:

  An area of interest: anything \[as_aoi()\] accepts. The raster covers
  its bounding box, so a non-rectangular area comes back with its
  corners filled in.

- product:

  Which model. \`"dtm"\` is bare ground, \`"dsm"\` is the surface
  including vegetation and buildings; subtracting one from the other
  over the same year is a canopy height model. For \[ortho_get()\]:
  \`"standard"\`, \`"high"\` or \`"true"\` (true orthophoto, buildings
  corrected to nadir).

- resolution:

  Pixel size in metres. Defaults to 1 m for elevation and 0.25 m for
  orthophotos, which is roughly the native detail of each.

- datum:

  Vertical reference system for elevation: \`"evrf2007"\` (the current
  national system) or \`"kron86"\` (the older one). Ignored for
  orthophotos.

- filename:

  Where to save it. \`NULL\` puts it in the cache and returns that path.

- convert:

  Convert an ASCII grid to GeoTIFF after downloading, which is lossless
  and strictly better: about a quarter of the size, and with the
  coordinate system attached. On by default; needs \`terra\`, and
  quietly keeps the ASCII grid if it is not installed. Orthophotos and
  the KRON86 terrain model already arrive as GeoTIFF and are untouched.

- mask:

  Cut the result to the outline of the area, not just to its bounding
  box. The coverage services are addressed by a bounding box, so without
  this a ragged area comes back with its corners filled in. Needs
  \`terra\`.

- max_pixels:

  Refuse requests larger than this many pixels per side. Measured on the
  terrain service: 1000 px returns in a second or two, 2000 px in under
  a minute, and 4000 px does not return at all. Raise it knowing that.

- quiet:

  Suppress progress messages.

- gdal:

  GDAL creation options for the written file, as a character vector.
  \`NULL\`, the default, writes DEFLATE with the predictor that suits
  the data, tiled, and BIGTIFF when the size calls for it.

- file:

  Former name of \`filename\`, kept working for now. Everything else in
  the package says \`filename\`, and one idea should not answer to two
  words.

## Value

The path to the raster: a GeoTIFF unless \`convert = FALSE\` left an
ASCII grid, which \[open_raster()\] will open with its coordinate system
attached.

## Details

Use these when you want a surface to work with. Use \[dem_request()\]
and friends when you want to know what was flown and when, or when you
need a vintage other than the current one – the coverage services
publish only the current model.

## Formats

The format is not a choice, it is a consequence of what each service
publishes: the terrain model in KRON86 comes as GeoTIFF, everything else
on the elevation side as ASCII grid, and orthophotos as GeoTIFF. ASCII
grids are bulky – a 1 km square at 1 m is about 16 MB against 4 MB for
the same thing as GeoTIFF – so convert once and keep the conversion if
you are going to use it repeatedly.

ASCII grids also carry no projection. \`terra::rast()\` opens them with
a CRS of \`NA\`, and a \`.prj\` sidecar does not help: GDAL's ASCII grid
driver ignores it, in WKT2 and in ESRI WKT1 alike. Both problems are why
\`convert = TRUE\` is the default. Use \[open_raster()\] for anything
fetched with \`convert = FALSE\`, or for ASCII grids from elsewhere.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(c(16.93, 52.41), buffer = 500)

terrain <- open_raster(dem_get(aoi, "dtm"))
surface <- open_raster(dem_get(aoi, "dsm"))
picture <- open_raster(ortho_get(aoi, "high"))

canopy <- surface - terrain
terra::plot(canopy)
} # }
```
