# Administrative boundaries for an area

Boundaries from the State Register of Borders, filtered to the area of
interest by the service rather than downloaded nationally and clipped
afterwards. Ask for the communes around a survey plot and three come
back, not two and a half thousand.

## Usage

``` r
prg_boundaries(
  aoi = NULL,
  level = "commune",
  max_features = 5000,
  quiet = FALSE
)
```

## Arguments

- aoi:

  An area of interest: anything \[as_aoi()\] accepts. \`NULL\` returns
  the whole country, which for communes means 2479 polygons – allowed,
  but ask for it deliberately.

- level:

  Which boundary. \`"commune"\`, \`"county"\` and \`"voivodeship"\` are
  the usual three; \`"cadastral_unit"\` and \`"cadastral_district"\` go
  finer, \`"town"\` and \`"country"\` sit alongside. \`"inspectorate"\`
  and \`"directorate"\` are the State Forests' units as the border
  register holds them, which is a different source from
  \[bdl_inspectorates()\] and useful precisely for that reason.

- max_features:

  Refuse to fetch more than this many.

- quiet:

  Suppress progress messages.

## Value

An \`sf\` data frame in EPSG:2180 with \`teryt\` (the national unit
code; a forest address prefix for the two forest levels), \`name\`,
\`level\`, \`area_ha\` as the register records it, and the boundary.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))

prg_boundaries(aoi, "commune")
prg_boundaries(aoi, "county")

# every voivodeship in the country
prg_boundaries(level = "voivodeship")
} # }
```
