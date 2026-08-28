# Find a forest unit by name

Turns "Metkow forest range, Chrzanow inspectorate" into a geometry you
can hand straight to any of the request functions. Matching ignores case
and Polish diacritics, so \`"Metkow"\` and \`"Mętków"\` both work.

## Usage

``` r
bdl_unit(directorate = NULL, inspectorate = NULL, range = NULL, quiet = FALSE)
```

## Arguments

- directorate:

  Regional directorate (RDLP) name, for example \`"Katowice"\`.

- inspectorate:

  Forest inspectorate (nadlesnictwo) name, for example \`"Chrzanow"\`.

- range:

  Forest range (lesnictwo) name, for example \`"Metkow"\`.

- quiet:

  Suppress progress messages.

## Value

An \`sf\` data frame in EPSG:2180 with the matched unit or units, the
forest address split into columns, and the names of the levels above it.
Pass it to \[as_aoi()\], or to any \`\*\_request()\` function directly.

## Details

The most specific level you name is the one returned: give \`range\` and
you get a forest range, give only \`inspectorate\` and you get the whole
inspectorate. The coarser arguments narrow the search rather than
changing the result, so pass them when a name is not unique.

## Examples

``` r
if (FALSE) { # \dontrun{
metkow <- bdl_unit(inspectorate = "Chrzanow", range = "Metkow")
metkow

# what imagery exists over it?
ortho_request(metkow)

# a whole inspectorate
bdl_unit(inspectorate = "Chrzanow")
} # }
```
