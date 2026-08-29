# rgeopl 0.3.0

* A URL repeated inside one selection is now fetched once. Two rows pointing at
  the same file resolved to the same target path, so both transfers wrote to one
  temporary file and raced each other. Every row still gets its path back; only
  the transfer is shared.
* `ortho_stack()` joins the CIR and RGB products of one flight into a single
  four-band raster: near-infrared, red, green, blue. `ortho_pairs()` lists the
  vintages that publish both, which is the question it raises.
  Measured before building it, on one sheet at 0.25 m: CIR's red and green
  correlate with RGB's at **0.999**, and its first band with nothing in RGB
  (0.19 to 0.47). The two products are one radiometric result cut two ways, so
  stacking them is sound -- and blue is the only band RGB actually contributes.
  A vegetation index therefore wants `bands = "cir"`, which halves the
  download: infrared and red already sit in one file, consistent with each
  other.
* `tile_mosaic()` gains `max_active`, so a stack can pass its connection limit
  down to the downloads.
* `mask` now works on the coverage side too: `dem_get()`, `ortho_get()` and
  `chm_get()` take it, and `chm_build()` takes an `aoi` to go with it. The
  coverage services are addressed by a bounding box, so until now a ragged
  stand came back through this path with its corners filled in while the same
  request through `tile_mosaic()` came back cut to the outline. One word should
  not mean two things depending on which way the data was fetched.

# rgeopl 0.2.0

## Many areas at once

Asking about hundreds of scattered plots used to mean asking about the country.
The bounding box drawn around 40 plots of 500 m radius covers 291 081 km2
against their own 31 km2, and the elevation index answered it with 1 410 846
records -- 936 times what the plots needed, assembled over tens of minutes and
then thrown away.

* `dem_request()`, `ortho_request()` and `pointcloud_request()` gain
  `by_feature`. Scattered areas are now asked about one feature at a time and
  the answers merged, with duplicate map sheets dropped. The default, `NULL`,
  decides by comparing the box around everything with the sum of the boxes
  around each part, so a single area or a tight cluster still goes out as one
  request.
* Those queries run concurrently, and so do downloads: `max_active`, defaulting
  to `getOption("rgeopl.max_active", 6)` and capped at 16.
* Measured on the same 40 plots: **1336 tiles in 7.2 s**, and 0.49 s on a
  second run, because each feature's answer is cached separately.
* Concurrency is `httr2::req_perform_parallel()` -- parallel I/O from one R
  process, not parallel R. That is deliberate: the download manifest is a
  read-modify-write of one file, and it stays correct only because the
  bookkeeping still runs on a single thread. The same work under multisession
  workers would race on that file and lose records without any error.
* Index queries now refuse a bounding box holding more than `max_records`
  (default 200 000) rather than grinding through it, and say to try
  `by_feature = TRUE`.
* A tile that fails to download leaves `NA` in `path` and a warning, instead of
  abandoning the rest of the batch.

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
