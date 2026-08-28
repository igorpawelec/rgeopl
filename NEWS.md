# rgeopl 0.1.0

First release. One area of interest, handed to every Polish national geodata
service in the form it expects, with server limits handled and everything
cached.

## Areas of interest

* `as_aoi()` takes an `sf`, `sfc` or `sfg` object, an `sf` bounding box, a
  `terra` `SpatVector`, `SpatRaster` or `SpatExtent`, a point or bounding box
  as bare numbers, a coordinate matrix, a file path, or WKT. For bare numbers
  the CRS is inferred from the coordinate range -- Poland's longitude/latitude
  window and the PL-1992 window do not overlap -- or the call fails rather than
  guessing.
* `aoi_bbox()` and `aoi_geom()` hand it on in whichever CRS a service needs.
* `rgeopl_example()` ships two real areas to experiment on: a point in a pine
  stand in Warmia, and a 600 ha survey area near Gniezno.

## What data exist: the GUGiK indexes

* `dem_request()`, `ortho_request()` and `pointcloud_request()` return one row
  per tile, with vintage, format, download link and the tile outline as
  geometry. Column names follow `rgugik`, so existing scripts port with a
  rename of the function call.
* The 1000-record ceiling on the underlying service is handled internally: the
  count is read first, and beyond one page the results are assembled by object
  id. A 40 x 40 km area returns 19 766 records in 20 requests, and a short
  result raises rather than passing as complete.
* `coverage()` reports how much of the area each vintage actually covers, and
  `plot_coverage()` draws it as small multiples, one panel per vintage.
* `tile_download()` fetches what survives your filtering; `tile_mosaic()` joins
  the tiles, cropping and masking to the area on request.

## Ready-made rasters: the GUGiK coverages

* `dem_get()` and `ortho_get()` return the current model clipped to the area,
  with no tiles to mosaic. ASCII grids are converted to GeoTIFF by default,
  which is lossless and about a quarter of the size.
* `chm_get()` and `chm_build()` produce a canopy height model, refusing to
  subtract two rasters that are not on the same grid.
* `open_raster()` attaches the coordinate system that ASCII grids do not carry.

## Forest Data Bank

* `bdl_directorates()`, `bdl_inspectorates()`, `bdl_ranges()`, `bdl_subareas()` and
  `bdl_compartments()` return the State Forests hierarchy for an area. Compartments are not
  published as vectors and are derived from the forest address.
* `bdl_unit()` finds a unit by name, ignoring case and Polish diacritics;
  `bdl_by_address()` finds one by forest address at any depth, from a regional
  directorate down to a single subarea.
* `bdl_catalogue()` and `bdl_overview()` list the whole country: 17 regional
  directorates, 429 forest inspectorates, 5259 forest ranges.
* `parse_forest_address()` splits the address into its seven fields.

## Administrative boundaries

* `prg_boundaries()` returns boundaries from the State Register of Borders for
  an area, filtered by the service rather than downloaded nationally and
  clipped. Nine levels, from the state border down to cadastral districts, plus
  the State Forests units as the border register holds them.

## Cache, progress and connections

* Index responses expire on a time-to-live; downloads are kept permanently and
  recorded, so a tile already on disk is never fetched twice. `cache_dir()`,
  `cache_info()` and `cache_clear()` manage it.
* Progress bars for index assembly, multi-file downloads and single large
  files. `options(rgeopl.progress = FALSE)` turns them off.
* Index queries and downloads have separate timeouts, because one should fail
  fast and the other legitimately takes minutes.

## Notes on the services, measured rather than assumed

These shaped the package and are worth knowing whether or not you use it.

* **The GUGiK services refuse connections from outside Poland.** The Forest
  Data Bank does not.
* **`returnIdsOnly` is not subject to the 1000-record cap**, which is how the
  index is assembled completely: one request returns all 1 637 675 object ids
  for the country.
* **The ArcGIS GeoJSON writer silently omits fields** of type
  `esriFieldTypeSingle`. On the orthophoto index that is the pixel size, which
  vanished with no error anywhere. Esri JSON is used instead.
* **One index field carries two units**: `char_przestrz` holds a grid spacing
  for rasters and a point density for point clouds, so they are split into
  `resolution` and `density`.
* **Acquisition dates are midnight UTC** and fall a day early when read in a
  local time zone west of Greenwich.
* **The Forest Data Bank stops offering `next` links after the second page**
  while still holding thousands of features, so paging is driven by explicit
  offsets against the total from the first request.
* **The border register reads a bounding box northing first**, in both CRS
  notations, and querying with the usual order returns a different part of the
  country without error.
* **A forest range's outline is not the set of subareas addressed to it.**
  Measured on one range: 144 subareas carry its address, 194 fall inside
  its polygon.
* **`a_year` in the Forest Data Bank is an edition stamp**, identical across
  the country, not the year a management plan was revised. There is no archive
  and no vintage to filter on.
* **Coverage measures map sheet outlines, not the imagery inside them.** A
  sheet that exists but is not filled still counts, so a coverage share of 1
  does not guarantee a mosaic without holes; `isFilled` is a separate question.
