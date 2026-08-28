# Define an area of interest

Normalises anything that describes a place in Poland into the internal
representation used by every client in this package.

## Usage

``` r
as_aoi(x, crs = NULL, buffer = 0)

is_aoi(aoi)
```

## Arguments

- x:

  One of: an \`sf\`, \`sfc\` or \`sfg\` object; an \`sf\` bounding box;
  a \`SpatVector\`, \`SpatRaster\` or \`SpatExtent\` (\`terra\`); a
  length-2 numeric vector (a single point, \`c(x, y)\`); a length-4
  numeric vector (a bounding box, \`c(xmin, ymin, xmax, ymax)\`); a
  two-column matrix of coordinates; a path to any file \`sf\` can read;
  or a WKT string.

- crs:

  Coordinate reference system of \`x\`, for inputs that do not carry
  one. Anything \`sf::st_crs()\` accepts. When \`NULL\` (default) and
  \`x\` is bare numeric, the CRS is inferred from the coordinate range:
  values inside Poland's longitude/latitude window are read as
  EPSG:4326, values inside the PL-1992 window as EPSG:2180. The two
  windows do not overlap, so the guess is either unambiguous or it fails
  loudly.

- buffer:

  Buffer in metres applied to the geometry. Applied in EPSG:2180, so the
  distance is a true ground distance. A point with \`buffer = 0\` stays
  a point, which is what you want when asking which tile contains a
  given location.

- aoi:

  An \`rgeopl_aoi\` object.

## Value

An object of class \`rgeopl_aoi\`.

## Examples

``` r
# a point given in lon/lat, CRS inferred
as_aoi(c(16.93, 52.41))
#> <rgeopl area of interest>
#>   type:     point
#>   features: 1
#>   CRS:      EPSG:4326
#>   bbox:     359245.4, 506913.6, 359245.4, 506913.6 (EPSG:2180)

# the same point with a 500 m buffer around it
as_aoi(c(16.93, 52.41), buffer = 500)
#> <rgeopl area of interest>
#>   type:     area
#>   features: 1
#>   CRS:      EPSG:2180
#>   bbox:     358745.4, 506413.6, 359745.4, 507413.6 (EPSG:2180)

# an explicit bounding box in PL-1992
as_aoi(c(571248, 151377, 572248, 152377), crs = 2180)
#> <rgeopl area of interest>
#>   type:     area
#>   features: 1
#>   CRS:      EPSG:2180
#>   bbox:     571248, 151377, 572248, 152377 (EPSG:2180)
```
