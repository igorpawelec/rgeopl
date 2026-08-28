# Geometry and bounding box of an area of interest

Geometry and bounding box of an area of interest

## Usage

``` r
aoi_geom(aoi, crs = CRS_PL1992)

aoi_bbox(aoi, crs = CRS_PL1992, by_feature = FALSE)
```

## Arguments

- aoi:

  An \`rgeopl_aoi\` object, or anything \[as_aoi()\] accepts.

- crs:

  Target CRS. Defaults to EPSG:2180, the CRS the GUGiK services use
  natively.

- by_feature:

  When \`TRUE\`, return one bounding box per feature instead of a single
  box around all of them. Useful for scattered areas, where one overall
  box would cover far more ground than was asked for.

## Value

\`aoi_geom()\` an \`sfc\`; \`aoi_bbox()\` a named numeric vector
(\`xmin\`, \`ymin\`, \`xmax\`, \`ymax\`), or a list of them when
\`by_feature\`.

## Examples

``` r
aoi <- as_aoi(c(16.93, 52.41), buffer = 250)
aoi_bbox(aoi)
#>     xmin     ymin     xmax     ymax 
#> 358995.4 506663.6 359495.4 507163.6 
aoi_bbox(aoi, crs = 4326)
#>     xmin     ymin     xmax     ymax 
#> 16.92633 52.40775 16.93367 52.41225 
```
