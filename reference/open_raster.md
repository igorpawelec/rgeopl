# Open a downloaded raster, with its coordinate system attached

A convenience for the one sharp edge in the coverage services: the
elevation models that come back as ASCII grids carry no projection
information at all. \`terra::rast()\` opens them with a CRS of \`NA\`,
and everything afterwards – overlays, distances, writing back out –
silently works in unknown units. The \`.prj\` sidecar that would
normally fix that is not read by GDAL's ASCII grid driver, so the CRS is
stamped here instead.

## Usage

``` r
open_raster(path, crs = 2180)
```

## Arguments

- path:

  Path returned by \[dem_get()\] or \[ortho_get()\].

- crs:

  CRS to assume when the file carries none. Defaults to EPSG:2180, which
  is what these services deliver.

## Value

A \`terra::SpatRaster\`.

## Details

GeoTIFFs already carry their CRS and pass through untouched.

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- as_aoi(c(16.93, 52.41), buffer = 300)

terrain <- open_raster(dem_get(aoi, "dtm"))
surface <- open_raster(dem_get(aoi, "dsm"))
canopy <- surface - terrain
terra::plot(canopy)
} # }
```
