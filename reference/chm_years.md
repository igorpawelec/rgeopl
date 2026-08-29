# Which vintages can make a canopy height model

A canopy model is one survey's surface model minus its own terrain
model, so it needs a vintage that published both, at one pixel size. Not
every one did: the terrain has been remapped far more often than the
surface, and a year with a terrain model alone cannot make a canopy
model at all.

## Usage

``` r
chm_years(aoi, quiet = FALSE)
```

## Arguments

- aoi:

  An area of interest: anything \[as_aoi()\] accepts.

- quiet:

  Suppress progress.

## Value

A data frame of \`year\`, \`resolution\` and the tile count of each
model, newest first, holding only the combinations that have both.

## See also

\[chm_get()\] to build one, and \[ortho_pairs()\] for the same question
asked of orthophotos.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(c(21.05, 53.80), buffer = 1000)

chm_years(aoi)                       # what the archive can do here
canopy <- chm_get(aoi, year = 2014, mask = TRUE)
} # }
```
