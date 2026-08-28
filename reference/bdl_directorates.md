# Forest administrative units and subareas

The Forest Data Bank publishes the State Forests' administrative
hierarchy and its subareas. Subareas are split across seventeen separate
collections, one per regional directorate; these functions hide that.
The directorates covering the area are looked up first (attributes only,
so it costs a fraction of a second) and only the relevant collections
are queried.

## Usage

``` r
bdl_directorates(aoi = NULL, within_aoi = TRUE, quiet = FALSE)

bdl_inspectorates(aoi = NULL, within_aoi = TRUE, quiet = FALSE)

bdl_ranges(aoi = NULL, within_aoi = TRUE, quiet = FALSE)

bdl_subareas(aoi, within_aoi = TRUE, max_features = 2e+05, quiet = FALSE)

bdl_compartments(aoi, within_aoi = TRUE, max_features = 2e+05, quiet = FALSE)
```

## Arguments

- aoi:

  An area of interest: anything \[as_aoi()\] accepts. Optional for the
  administrative levels, required for subareas, which are far too
  numerous to fetch blind.

- within_aoi:

  Keep only features that actually meet the area. The service filters by
  bounding box alone, so for anything other than a rectangle it also
  returns features lying beside the area. Features that straddle the
  boundary are kept whole, not clipped, so their recorded areas stay
  true.

- quiet:

  Suppress progress messages.

- max_features:

  Refuse to fetch more than this many features. Raise it deliberately
  rather than by accident.

## Value

An \`sf\` data frame in EPSG:2180 with the forest address parsed into
columns (see \[parse_forest_address()\]), \`year\` (the management plan
vintage the unit is on) and the names of whichever administrative levels
the collection carries.

## Address or geometry

\`within_aoi\` filters by geometry, which is what "subareas in this
area" means. It is not the same as "subareas of this unit": a forest
range's outline overlaps subareas belonging to its neighbours. Measured
on the Turnica range, 04-02-2-11: 144 subareas carry its address,
totalling 1187 ha, while 194 subareas fall inside its polygon, totalling
1615 ha – 50 of them addressed to four other ranges. When you mean the
unit rather than the area, go through \[bdl_by_address()\], which
filters on the address.

## No archive

These services publish the \*\*current state only\*\*, and there is no
vintage to filter on either: \`year\` (\`a_year\` upstream) is the
edition stamp of the BDL release, identical across the whole country –
measured 2026 for all 429 forest inspectorates and for every subarea
sampled. It does not say when a unit's management plan was revised. A
time series has to be built from your own snapshots. This is the one
respect in which BDL is poorer than the GUGiK indexes, where every
vintage stays available and is queryable.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))

bdl_directorates(aoi)     # regional directorate (RDLP)
bdl_inspectorates(aoi)   # forest inspectorate (nadlesnictwo)
bdl_ranges(aoi)      # forest range (lesnictwo)

st <- bdl_subareas(aoi)          # subareas (wydzielenia)
bl <- bdl_compartments(aoi)          # compartments (oddzialy), dissolved from the address

# everything in one forest range
subset(st, range_cd == "06")
} # }
```
