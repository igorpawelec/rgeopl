# Package index

## Area of interest

One representation of “where”, handed to each service in the form and
the coordinate system it expects.

- [`as_aoi()`](https://igorpawelec.github.io/rgeopl/reference/as_aoi.md)
  [`is_aoi()`](https://igorpawelec.github.io/rgeopl/reference/as_aoi.md)
  : Define an area of interest
- [`aoi_geom()`](https://igorpawelec.github.io/rgeopl/reference/aoi_geom.md)
  [`aoi_bbox()`](https://igorpawelec.github.io/rgeopl/reference/aoi_geom.md)
  : Geometry and bounding box of an area of interest
- [`rgeopl_example()`](https://igorpawelec.github.io/rgeopl/reference/rgeopl_example.md)
  : Example areas of interest shipped with the package

## What data exist here

The indexes, one row per tile: vintage, format, download link and the
tile outline. Nothing is downloaded until you ask.

- [`dem_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  [`pointcloud_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  [`ortho_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  : What elevation, point cloud and orthophoto data exist for an area
- [`coverage()`](https://igorpawelec.github.io/rgeopl/reference/coverage.md)
  [`plot_coverage()`](https://igorpawelec.github.io/rgeopl/reference/coverage.md)
  : Summarise and draw index coverage by vintage
- [`tile_download()`](https://igorpawelec.github.io/rgeopl/reference/tile_download.md)
  : Download the tiles an index points to
- [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md)
  : Join downloaded tiles into one raster
- [`ortho_stack()`](https://igorpawelec.github.io/rgeopl/reference/ortho_stack.md)
  : Orthophoto as one four-band raster
- [`ortho_pairs()`](https://igorpawelec.github.io/rgeopl/reference/ortho_pairs.md)
  : Which orthophoto vintages publish both products
- [`pointcloud_get()`](https://igorpawelec.github.io/rgeopl/reference/pointcloud_get.md)
  : Point cloud tiles as a catalogue ready for lidR

## Ready-made rasters

The coverage services: the current model clipped to your area, with no
tiles to mosaic. Point clouds are not available this way.

- [`dem_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  [`ortho_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  : Download an elevation model or an orthophoto for an area
- [`chm_get()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  [`chm_build()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  : Canopy height for an area
- [`chm_years()`](https://igorpawelec.github.io/rgeopl/reference/chm_years.md)
  : Which vintages can make a canopy height model
- [`open_raster()`](https://igorpawelec.github.io/rgeopl/reference/open_raster.md)
  : Open a downloaded raster, with its coordinate system attached

## Forest units

The State Forests hierarchy, searchable by name or by forest address,
and the stand subareas underneath it.

- [`bdl_directorates()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md)
  [`bdl_inspectorates()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md)
  [`bdl_ranges()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md)
  [`bdl_subareas()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md)
  [`bdl_compartments()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md)
  : Forest administrative units and subareas
- [`bdl_unit()`](https://igorpawelec.github.io/rgeopl/reference/bdl_unit.md)
  : Find a forest unit by name
- [`bdl_by_address()`](https://igorpawelec.github.io/rgeopl/reference/bdl_by_address.md)
  : Find a forest unit by its address
- [`bdl_catalogue()`](https://igorpawelec.github.io/rgeopl/reference/bdl_catalogue.md)
  : List every forest unit in Poland
- [`bdl_overview()`](https://igorpawelec.github.io/rgeopl/reference/bdl_overview.md)
  : The State Forests at a glance
- [`parse_forest_address()`](https://igorpawelec.github.io/rgeopl/reference/parse_forest_address.md)
  : Split a forest address into its parts

## Administrative boundaries

- [`prg_boundaries()`](https://igorpawelec.github.io/rgeopl/reference/prg_boundaries.md)
  : Administrative boundaries for an area

## Looking at what you got

- [`plot_units()`](https://igorpawelec.github.io/rgeopl/reference/plot_units.md)
  : Draw forest units, with context

## Cache

Index responses expire on their own; downloads are kept and recorded, so
a tile already on disk is never fetched twice.

- [`cache_dir()`](https://igorpawelec.github.io/rgeopl/reference/cache_dir.md)
  [`cache_set_dir()`](https://igorpawelec.github.io/rgeopl/reference/cache_dir.md)
  : Cache location
- [`cache_info()`](https://igorpawelec.github.io/rgeopl/reference/cache_info.md)
  [`cache_clear()`](https://igorpawelec.github.io/rgeopl/reference/cache_info.md)
  : Inspect and prune the download cache
- [`rgeopl-options`](https://igorpawelec.github.io/rgeopl/reference/rgeopl-options.md)
  : Package options
