# Which orthophoto vintages publish both products

The first question \[ortho_stack()\] raises: a four-band image needs a
flight whose CIR and RGB were both published, at the same pixel size.

## Usage

``` r
ortho_pairs(index)
```

## Arguments

- index:

  An orthophoto index from \[ortho_request()\].

## Value

A data frame of \`year\`, \`resolution\` and the tile count of each
composition, newest first, keeping only the combinations that have both.

## See also

\[ortho_stack()\]

## Examples

``` r
if (FALSE) { # \dontrun{
ortho_pairs(ortho_request(as_aoi(c(16.80, 52.44), buffer = 600)))
} # }
```
