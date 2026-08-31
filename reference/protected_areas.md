# Protected areas covering an area of interest

Nature conservation as the register holds it: Natura 2000 sites,
reserves, national and landscape parks, ecological corridors and the
rest. The question a stand raises the moment you have its outline –
whether anything protected lies under it – and one the Forest Data Bank
cannot answer, because it publishes no conservation data at all.

## Usage

``` r
protected_areas(
  aoi = NULL,
  type = "all",
  within_aoi = TRUE,
  max_features = 2e+05,
  quiet = FALSE
)
```

## Arguments

- aoi:

  An area of interest: anything \[as_aoi()\] accepts. \`NULL\` fetches
  the whole country, which every one of these layers is small enough
  for.

- type:

  Which registers to ask. \`"all"\` asks every one; otherwise any of
  \`"natura2000"\` (both directives at once), \`"birds"\`,
  \`"habitats"\`, \`"reserves"\`, \`"national_parks"\`,
  \`"landscape_parks"\`, \`"protected_landscape"\`, \`"corridors"\`,
  \`"ramsar"\`, \`"ecological_sites"\`, \`"landscape_complexes"\`,
  \`"documentation_sites"\`, \`"monuments_area"\`,
  \`"monuments_point"\`. More than one may be named.

- within_aoi:

  Keep only features that actually meet the area. The service filters by
  bounding box alone, so for anything other than a rectangle it also
  returns features lying beside it.

- max_features:

  Refuse a request larger than this. The service cannot page, so this is
  a ceiling on one answer rather than on a walk.

- quiet:

  Suppress progress messages.

## Value

An \`sf\` data frame in EPSG:2180 with \`type\` naming the register the
row came from, \`name\`, \`code\` (the Natura 2000 site code, \`NA\`
elsewhere) and \`inspire_id\`, followed by whatever else the layer
carries.

## What the rows are

A park and its buffer zone are separate features, both in the park layer
and both named after the park: \`ParkiNarodowe\` holds 46 rows for
Poland's 23 national parks, half of them \`... - otulina\`. Summing
areas without looking will count the same ground twice.

## See also

\[bdl_subareas()\] for the stands themselves.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))

protected_areas(aoi)
protected_areas(aoi, "natura2000")

# every reserve in the country, in one request
protected_areas(type = "reserves")
} # }
```
