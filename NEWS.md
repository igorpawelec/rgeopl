# rgeopl (development version)

* `cache_clear()` no longer forgets files it could not delete. It rewrote the
  manifest whether or not the removal succeeded, so a file still held open --
  which on Windows a `SpatRaster` in the session is enough to do -- stayed on
  disk while the manifest dropped its row. `cache_info()` then reported an
  empty cache with a file sitting in it, and nothing would ever clean it up or
  reuse it. Only rows whose file has actually gone are dropped now, and what
  resisted is named in a warning.
* The BDL side checks that it got everything, which until now only the GUGiK
  side did. `oapif_properties()` and `oapif_catalogue()` asked for a fixed
  number of records and returned whatever came back: today that is 5259 forest
  ranges against a ceiling of 10 000, but a collection growing past its
  ceiling would have been truncated in silence -- which is the failure this
  package was written to fix, and it was in our own code.
* A collection whose service does not report how many features it holds is now
  paged until a page comes back short, rather than crashing. The missing count
  was handled as `NA` in three places and then passed to `seq_len()`, which
  ends in `argument must be coercible to non-negative integer`. Some services
  really do omit it -- the GDOS one does.

* `dem_to_datum()` converts an elevation model between Poland's two height
  systems. Measured over the country, an EVRF2007 height is 13.6 to 19.2 cm
  above the KRON86 height of the same ground, so comparing terrain across the
  2019 change of datum without converting reports about 17 cm of settlement
  that is not there. A canopy model does not need it -- surface and terrain
  are measured in the same system and it cancels.

  This exists because `sf::st_transform()` cannot be used for it. PROJ knows
  the right transformation, at 0.04 m, but cannot obtain the grid it needs;
  the operation it can instantiate is `+proj=noop`, which returns the heights
  unchanged and relabelled. What PROJ can fetch is the pair of quasi-geoid
  models GUGiK publishes, and going up to the ellipsoid through one and back
  down through the other gives the same answer. Checked against those two
  models read directly: agreement to 0.0000 m.

  Two things were measured rather than assumed. Given a pipeline, `sf` passes
  coordinates in the authority axis order -- latitude first for EPSG:4326,
  northing first for EPSG:2180 -- so the pipeline swaps them back; a version
  routed through PL-1992 without that is out by up to 11 mm and returns
  nothing at all for Zakopane. And the shift is sampled on a lattice rather
  than per cell: at the default 1000 m that costs at most 0.67 mm against a
  250 m lattice, on models accurate to 30 mm.

# rgeopl 0.4.0

* `pointcloud_get()` carries the point cloud chain as far as it can go without
  leaving CRAN behind: it downloads what an index points at, checks the
  selection is one survey, and returns the files with the coordinate system
  the archive says they are in. That last part is the reason it exists. Read
  straight out of the LAS headers, a 2024 tile declares EPSG:2180 while the
  2012 and 2014 tiles carry a projection record three bytes long, which is to
  say empty -- and a catalogue with no coordinate system is the kind of thing
  that goes unnoticed until an overlay lands in the wrong place.

  It stops one line short of a `lidR` catalogue on purpose. `lidR` was
  archived from CRAN on 2026-06-09 together with `rlas`, and there is no way
  to reach it that leaves a check clean: naming it in `Suggests` or in
  `Enhances` makes dependency resolution fetch it from a repository that no
  longer carries it and fail, while calling `requireNamespace()` without
  declaring it raises a check WARNING. All three measured, the last one on
  four platforms at once. `?pointcloud_get` gives the line to write, and where
  `lidR` still installs from.

* `chm_get()` takes a `year`. Without one it uses the coverage services as
  before, which publish the current model and nothing else; with one it
  assembles the model from archive tiles, which is the only route to an
  earlier flight and the route people were walking by hand. `chm_years()`
  lists the vintages an area can make a canopy model from at all -- not many
  can, because the terrain has been remapped far more often than the surface.
* `dem_request()` and `pointcloud_request()` take a `format`. The service
  publishes one map sheet in several forms at once -- measured across three
  distant areas, 178 of 1028 sheet/product/vintage combinations come in more
  than one, and some in three -- and only `"grid"` is a raster. The others
  are text lists of points and triangulated models, which look like extra
  tiles until something downstream refuses them.
* Tiles are joined through a GDAL virtual raster instead of being read into
  memory one by one. Measured on 15 orthophoto tiles, 586 MB, cut to an 800 m
  square: **175 s before, 0.8 s after**, with not one cell of 17.3 million
  differing. On 15 elevation tiles the same cut went from 13.2 s to 0.6 s.
  The old path also materialised the whole join before cropping it, which for
  those orthophoto tiles meant asking the disk for 17 GB of uncompressed
  scratch space -- enough to fail outright, which is how this was found.
* The cache manifest is read once per batch and written once per batch, rather
  than once per file. It is a single table for the whole cache and it only
  grows, so the old way got slower the longer the package was used: a
  1336-tile job spent 10 s on bookkeeping with 1500 rows in the manifest and
  **125 s with 50 000**. Both now take under a fifth of a second.
* Single downloads stream to disk instead of being assembled in memory first,
  which is what the parallel path already did. A point cloud tile no longer
  costs its own size in RAM before it reaches the cache.
* `tile_mosaic()` refuses a selection that mixes file formats, and says so.
  Every elevation sheet is published twice under one sheet number, as a grid
  and as a list of points; picking both was previously reported as a duplicate
  sheet, and the advice given for that case did not help.

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
