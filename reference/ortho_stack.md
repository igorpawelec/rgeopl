# Orthophoto as one four-band raster

Joins the CIR and RGB products of the same flight into a single raster
with near-infrared, red, green and blue. Downloads what it needs,
mosaics each product, and stacks them.

## Usage

``` r
ortho_stack(
  index,
  aoi = NULL,
  crop = c("aoi", "tiles"),
  mask = FALSE,
  bands = c("nrgb", "cir"),
  year = NULL,
  resolution = NULL,
  filename = NULL,
  overwrite = FALSE,
  max_active = NULL,
  quiet = FALSE
)
```

## Arguments

- index:

  An orthophoto index from \[ortho_request()\].

- aoi:

  The area to cut to, as in \[tile_mosaic()\].

- crop, mask:

  Passed to \[tile_mosaic()\]. \`crop = "aoi"\` cuts to the area, \`mask
  = TRUE\` also cuts to its outline.

- bands:

  \`"nrgb"\` for all four; \`"cir"\` for infrared, red and green alone,
  which halves the download and is all a vegetation index needs.

- year, resolution:

  Which flight to use. \`NULL\` picks the most recent vintage that
  publishes both products, at its finest pixel. See \[ortho_pairs()\]
  for what is on offer.

- filename:

  Write the result here.

- overwrite, max_active, quiet:

  Passed through to the download.

## Value

A \`terra::SpatRaster\` whose layers are named \`NIR\`, \`R\`, \`G\` and
\`B\`, or \`NIR\`, \`R\`, \`G\` with \`bands = "cir"\`.

## Why not an argument to \`tile_mosaic()\`

\[tile_mosaic()\] refuses to join tiles of different band compositions,
and that refusal is the point: RGB and CIR laid side by side in one
mosaic would make band 1 mean two different things in two halves of the
picture. Stacking them is a different operation – spectral rather than
spatial – so it gets its own verb rather than a flag that switches the
guard off.

## See also

\[ortho_pairs()\], \[tile_mosaic()\].

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
idx <- ortho_request(aoi)

ortho_pairs(idx)                       # which vintages have both products

nrgb <- ortho_stack(idx, aoi, mask = TRUE)
terra::plotRGB(nrgb, r = 1, g = 2, b = 3)   # false colour: vegetation red

ndvi <- (nrgb[["NIR"]] - nrgb[["R"]]) / (nrgb[["NIR"]] + nrgb[["R"]])
} # }
```
