# Canopy height for an area

Fetches the surface and terrain models over an area and subtracts one
from the other. \`chm_get()\` downloads both; \`chm_build()\` does the
arithmetic on rasters you already have.

## Usage

``` r
chm_get(
  aoi,
  resolution = 1,
  datum = c("evrf2007", "kron86"),
  keep = c("chm", "all"),
  min_height = NULL,
  mask = FALSE,
  filename = NULL,
  max_pixels = 2500,
  quiet = FALSE
)

chm_build(
  surface,
  terrain,
  aoi = NULL,
  keep = c("chm", "all"),
  min_height = NULL,
  mask = FALSE,
  filename = NULL,
  quiet = FALSE
)
```

## Arguments

- aoi:

  The area to cut to when \`mask = TRUE\`. Ignored otherwise.

- resolution:

  Pixel size in metres. Both models are requested at the same one, which
  is what puts them on the same grid.

- datum:

  Vertical reference system, \`"evrf2007"\` or \`"kron86"\`. It cancels
  in the subtraction, so it matters only if you also want the inputs.

- keep:

  \`"chm"\` returns the canopy model alone; \`"all"\` returns a list of
  all three rasters, canopy, surface and terrain, when you want to look
  at what went into it.

- min_height:

  Heights below this become \`NA\`. \`NULL\`, the default, changes
  nothing. Setting it to \`0\` removes the small negative values that
  come from noise in the two models; note that this drops those cells
  rather than flattening them to zero, so it does not invent ground
  where there was none.

- mask:

  Cut the result to the outline of the area rather than to its bounding
  box, so a ragged stand comes back without its corners filled in. For
  \[chm_build()\] this needs \`aoi\` as well.

- filename:

  Write the canopy model here.

- max_pixels:

  Passed to \[dem_get()\].

- quiet:

  Suppress progress.

- surface, terrain:

  Surface and terrain models: file paths, or \`terra::SpatRaster\`
  objects.

## Value

A \`terra::SpatRaster\`, or with \`keep = "all"\` a list of three named
\`chm\`, \`surface\` and \`terrain\`.

## See also

\[dem_get()\] for the models on their own, and \[coverage()\] to check
whether a canopy model is possible from the archive at all – these
coverage services publish only the current one.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(c(16.80, 52.44), buffer = 400)

canopy <- chm_get(aoi, resolution = 1)
terra::plot(canopy)

# keep what went into it, and drop the noise below ground
parts <- chm_get(aoi, keep = "all", min_height = 0)
terra::plot(parts$surface)
} # }
```
