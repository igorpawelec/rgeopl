# Convert an elevation model between Poland's two height systems

Heights measured in PL-KRON86-NH and in PL-EVRF2007-NH are not
comparable. Measured over Poland, an EVRF2007 height is 13.6 to 19.2 cm
above the KRON86 height of the same ground, and by how much depends on
where you are. The archive holds both, so any comparison of terrain
spanning the 2019 change of datum needs one side converted first.

## Usage

``` r
dem_to_datum(
  x,
  from = c("kron86", "evrf2007"),
  to = c("evrf2007", "kron86"),
  step = 1000,
  filename = NULL,
  quiet = FALSE
)
```

## Arguments

- x:

  An elevation model: a \`terra::SpatRaster\` or a path to one.

- from, to:

  The height systems, \`"kron86"\` for PL-KRON86-NH and \`"evrf2007"\`
  for PL-EVRF2007-NH. The index reports which a tile is in, in its
  \`VRS\` column.

- step:

  How finely to sample the shift, in metres. The shift is the difference
  of two quasi-geoid models and changes by 5.5 cm over the whole
  country, so it is sampled on a lattice and interpolated between
  samples rather than computed per cell. Measured against a 250 m
  lattice, the default 1000 m costs at most 0.67 mm and 2000 m costs 1.3
  mm – against models that are themselves accurate to 30 mm.

- filename:

  Write the result here.

- quiet:

  Suppress progress.

## Value

A \`terra::SpatRaster\` of the same geometry as \`x\`, with heights in
the \`to\` system.

## Details

A canopy height model does not: surface and terrain are measured in the
same system and it cancels in the subtraction. This is for comparing
\*terrain\* with terrain – subsidence, erosion, earthworks – where the
datum does not cancel and about 17 cm of phantom change is the result of
ignoring it.

## What it needs, and what it refuses

The two quasi-geoid grids are downloaded from PROJ's own content
delivery network the first time they are used, and cached by PROJ
afterwards. This function turns that network on for the duration of the
call and puts the setting back as it found it.

It fails rather than guesses in three cases: the grids cannot be
reached, the area lies outside their coverage, or the computed shift is
exactly zero everywhere – which is what a silent \`+proj=noop\` looks
like from here.

## See also

\[dem_request()\], whose \`VRS\` column says which system a tile is in,
and \[chm_get()\], which does not need this.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(c(21.05, 53.80), buffer = 1000)
idx <- dem_request(aoi, format = "grid")

# a 2014 terrain model is in PL-KRON86-NH
old <- tile_mosaic(subset(idx, product == "DTM" & year == 2014), aoi)
old_evrf <- dem_to_datum(old, from = "kron86", to = "evrf2007")

# now it can be compared with a model published in the current system
terra::plot(old_evrf - old)   # the shift itself, about 0.16 m here
} # }
```
