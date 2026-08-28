# Split a forest address into its parts

The State Forests address (\*adres lesny\*) is a fixed-width string, 25
characters, seven dash-separated fields: regional directorate, forest
inspectorate, sub-district, forest range, compartment, subarea and part.
Higher administrative levels leave the lower fields blank rather than
omitting them, so the positions are the same everywhere and can be read
directly.

## Usage

``` r
parse_forest_address(x)
```

## Arguments

- x:

  Character vector of forest addresses, for example \`"09-01-2-10-187 -f
  -00"\`.

## Value

A data frame with columns \`directorate_cd\`, \`inspectorate_cd\`,
\`obreb_cd\`, \`range_cd\`, \`compartment\`, \`subarea\` and \`part\`.
Blank fields become \`NA\`, so a forest inspectorate's address gives an
inspectorate code and nothing below it.

## Examples

``` r
parse_forest_address(c("09-01-2-10-187   -f   -00",
                       "09-02-1-06-33A   -c   -00",
                       "09-12- -  -      -    -"))
#>   directorate_cd inspectorate_cd obreb_cd range_cd compartment subarea part
#> 1             09              01        2       10         187       f   00
#> 2             09              02        1       06         33A       c   00
#> 3             09              12     <NA>     <NA>        <NA>    <NA> <NA>
```
