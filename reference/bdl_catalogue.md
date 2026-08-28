# List every forest unit in Poland

A flat table of the State Forests' administrative hierarchy: codes,
names, the forest address, and the BDL edition stamp. No geometry, so it
is fast enough to work with interactively.

## Usage

``` r
bdl_catalogue(level = c("inspectorate", "range", "directorate"))
```

## Arguments

- level:

  \`"directorate"\` (RDLP), \`"inspectorate"\` (nadlesnictwo) or
  \`"range"\` (lesnictwo). Each level carries the names of the levels
  above it.

## Value

A data frame, one row per unit, sorted by forest address.

## Details

\`year\` is the edition of the BDL release, not the year a unit's
management plan was revised: it reads 2026 for all 429 inspectorates and
for every subarea sampled. It is kept because a future release could
stamp editions unevenly, but today it distinguishes nothing.

## See also

\[bdl_overview()\] for the same thing summarised by directorate.

## Examples

``` r
if (FALSE) { # \dontrun{
inspectorates <- bdl_catalogue("inspectorate")
nrow(inspectorates)
head(inspectorates)

# how many forest ranges does each inspectorate run?
ranges <- bdl_catalogue("range")
sort(table(ranges$inspectorate_name), decreasing = TRUE)[1:10]

# which inspectorates are split into three or more sub-districts?
obrebs <- tapply(ranges$obreb_cd, ranges$adr_for, function(z) length(unique(z)))
names(obrebs)[obrebs >= 3]
} # }
```
