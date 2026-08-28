# Example areas of interest shipped with the package

Two small vector files from real work in Polish forests, so that the
examples in this package point at somewhere data actually exists rather
than at made-up coordinates.

## Usage

``` r
rgeopl_example(name = NULL)
```

## Arguments

- name:

  File name, for example \`"test_lasow.shp"\`. Omit to list what is
  available.

## Value

The path to the file, or a character vector of available names.

## Details

- \`test_lasow.shp\`:

  A single point in a Scots pine stand in the Wipsowo forest
  inspectorate (Olsztyn regional directorate), Warmia. Useful for asking
  what exists at one spot: seven elevation vintages, but only one
  airborne laser scan.

- \`gleboczek_aoi.shp\`:

  Two polygons, about 600 ha together, near Gniezno in Wielkopolska. A
  realistic survey area: multi-feature, detailed boundaries, and large
  enough that the index runs to several pages.

Both are in EPSG:2180 (PL-1992).

## Examples

``` r
rgeopl_example()
#> [1] "gleboczek_aoi.shp" "test_lasow.shp"   

aoi <- as_aoi(sf::st_read(rgeopl_example("gleboczek_aoi.shp"), quiet = TRUE))
aoi
#> <rgeopl area of interest>
#>   type:     area
#>   features: 2
#>   CRS:      EPSG:2180
#>   bbox:     416481.7, 535097.9, 420166.4, 538071.9 (EPSG:2180)
```
