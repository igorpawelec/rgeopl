# Changelog

## rgeopl (development version)

- A byte mosaic keeps its brightest pixels after all. The narrowing that
  was meant to stop terra marking 255 as missing asked the raster for
  its range and gave up when it did not have one – which is what a
  virtual raster always answers, and every mosaic here is built through
  one. So the guard was absent from precisely the path it was written
  for. The range is computed now when it is not already known.
- `narrow_type()` no longer stops on a raster that holds no values; it
  gives up quietly instead, which is what the caller expects of it.
- [`dem_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  and
  [`ortho_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  take `gdal`, like every other function here that writes a file. They
  were the only two that wrote one without letting you say how.

## rgeopl 0.7.0

- Two vignettes for the raster half of the package, which the narrative
  documentation had never covered: *Rasters end to end* takes an area
  from the index through mosaicking, canopy height, four-band
  orthophotos and point clouds to a written file, and *Heights, and the
  two systems Poland measures them in* is about the vertical datums.
  Between them they reach the functions that do the work: 22 of the 39
  exported ones appeared in no vignette at all, including
  [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md),
  [`chm_get()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  and
  [`ortho_stack()`](https://igorpawelec.github.io/rgeopl/reference/ortho_stack.md).
- [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md)
  takes a `datum`. Mixing vertical systems is refused, because the seam
  would be a step in the ground that is not there – but it is the one
  refusal with a way through: named a system to land in, it mosaics each
  side on its own, converts the one that is in the other, and joins them
  with the target laid down first. Naming a datum also accepts the
  mixture of vintages that comes with it, since two vertical systems are
  two flights and there is no way to have one without the other.
- [`chm_build()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  takes `vrs`, the vertical systems of the two rasters, and converts
  before subtracting when they differ. Rasters carry no vertical system,
  so it cannot be worked out from them – and the trap is ordinary:
  Białowieża publishes a 2018 surface and a 2022 terrain, and
  subtracting them as they come makes every canopy about 16 cm too
  short.
- A byte raster keeps its brightest pixels. terra writes one with the
  missing value set to 255, and in an orthophoto 255 is sky, bright
  roofs and saturated ground: measured, 20 pixels of 255 written and 0
  read back, with 20 NAs in their place. Every write now goes through
  one function that names the narrowest type the values fit in and
  leaves the tag off when there is nothing missing to mark. Rasters that
  do have gaps keep the wider type that can hold them.
- The functions people actually type are tested against recorded
  answers. Everything else in the suite is offline with the answers made
  up, which left the entry points uncovered – when `format` was added to
  [`dem_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  and every later argument shifted one place, nothing noticed. Ten of
  them now replay real responses through `httptest2`. The recordings
  stay in the repository rather than the built package: these services
  nest deeply enough that the mirrored paths run past the 100 bytes a
  tarball can portably store.

## rgeopl 0.6.0

- [`protected_areas()`](https://igorpawelec.github.io/rgeopl/reference/protected_areas.md)
  answers the question a stand outline raises immediately: whether
  anything protected lies under it. Natura 2000 under both directives,
  reserves, national and landscape parks, protected landscape areas,
  ecological corridors, Ramsar sites, ecological sites, landscape
  complexes, documentation sites and natural monuments – thirteen
  registers from GDOŚ, the body that keeps them. The Forest Data Bank
  draws protected areas on its maps and publishes none of them as data:
  its whole public service is seven layers of administrative units and
  subareas, measured.

  Two things about the service had to be measured rather than assumed.
  The spelling of the coordinate system in the bounding box decides the
  axis order – `EPSG:2180` means easting first and
  `urn:ogc:def:crs:EPSG::2180` means northing first – and mismatching
  them returns an empty answer for an area full of reserves, with no
  error. That also explains
  [`prg_boundaries()`](https://igorpawelec.github.io/rgeopl/reference/prg_boundaries.md),
  which uses the urn spelling and reverses its bounding box: not a quirk
  of PRG but the rule. And the service cannot page at all: `STARTINDEX`
  answers `Cannot do natural order without a primary key`, so each
  request is one request, bounded by `max_features` and checked against
  the reported total.

  A park and its buffer zone are separate features under the same name:
  `ParkiNarodowe` returns 46 rows for Poland’s 23 national parks,
  exactly 23 of them buffer zones.
  [`?protected_areas`](https://igorpawelec.github.io/rgeopl/reference/protected_areas.md)
  says so, because summing areas without looking counts the same ground
  twice.

## rgeopl 0.5.0

- [`dem_to_datum()`](https://igorpawelec.github.io/rgeopl/reference/dem_to_datum.md)
  converts an elevation model between Poland’s two height systems.
  Measured over the country, an EVRF2007 height is 13.6 to 19.2 cm above
  the KRON86 height of the same ground, so comparing terrain across the
  2019 change of datum without converting reports about 17 cm of
  settlement that is not there. A canopy model does not need it –
  surface and terrain are measured in the same system and it cancels.

  This exists because
  [`sf::st_transform()`](https://r-spatial.github.io/sf/reference/st_transform.html)
  cannot be used for it. PROJ knows the right transformation, at 0.04 m,
  but cannot obtain the grid it needs; the operation it can instantiate
  is `+proj=noop`, which returns the heights unchanged and relabelled.
  What PROJ can fetch is the pair of quasi-geoid models GUGiK publishes,
  and going up to the ellipsoid through one and back down through the
  other gives the same answer. Checked against those two models read
  directly: agreement to 0.0000 m.

  Two things were measured rather than assumed. Given a pipeline, `sf`
  passes coordinates in the authority axis order – latitude first for
  EPSG:4326, northing first for EPSG:2180 – so the pipeline swaps them
  back; a version routed through PL-1992 without that is out by up to 11
  mm and returns nothing at all for Zakopane. And the shift is sampled
  on a lattice rather than per cell: at the default 1000 m that costs at
  most 0.67 mm against a 250 m lattice, on models accurate to 30 mm.

- Every raster the package writes is DEFLATE now, with the predictor the
  data calls for, tiled, and BIGTIFF when the size warrants it. Four of
  the six places that write a file passed no options at all and so got
  terra’s default, which is LZW: measured on a 2369 x 2114 float tile,
  11.2 MB against 8.3 MB, in the same 0.8 s. The predictor is not a free
  choice – GDAL refuses PREDICTOR=3 on integers outright, which a single
  blanket setting would have done to every orthophoto – so it follows
  the data type, which also fixes the masking path quietly using the
  integer predictor on elevation models.
  [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md),
  [`chm_get()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md),
  [`chm_build()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md),
  [`ortho_stack()`](https://igorpawelec.github.io/rgeopl/reference/ortho_stack.md)
  and
  [`dem_to_datum()`](https://igorpawelec.github.io/rgeopl/reference/dem_to_datum.md)
  take `gdal` to replace all of that when you want something else, a
  Cloud Optimized GeoTIFF for instance.

- Mosaic layers are named from the index rather than after the temporary
  file they were built through. A written mosaic carried a band
  description like `filedc437e7148b` – a name random per session, stored
  in the file, outliving the session that made it. Now an elevation
  mosaic says `DTM` and a three-band orthophoto says `R, G, B` or
  `NIR, R, G` by its composition.

- [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md)
  refuses a selection the virtual raster could only join in part.
  [`terra::vrt()`](https://rspatial.github.io/terra/reference/vrt.html)
  leaves out a file it cannot fit and reports it in a warning that
  scrolls past, which leaves a mosaic with a hole in it that looks
  finished; measured, it drops a tile with a different band count or a
  different coordinate system, while resolutions and offset grids it
  accepts and resamples. The sources the VRT actually took are counted –
  as distinct names, since a multi-band file is listed once per band –
  and anything missing is an error rather than a warning.

- [`cache_clear()`](https://igorpawelec.github.io/rgeopl/reference/cache_info.md)
  no longer forgets files it could not delete. It rewrote the manifest
  whether or not the removal succeeded, so a file still held open –
  which on Windows a `SpatRaster` in the session is enough to do –
  stayed on disk while the manifest dropped its row.
  [`cache_info()`](https://igorpawelec.github.io/rgeopl/reference/cache_info.md)
  then reported an empty cache with a file sitting in it, and nothing
  would ever clean it up or reuse it. Only rows whose file has actually
  gone are dropped now, and what resisted is named in a warning.

- The BDL side checks that it got everything, which until now only the
  GUGiK side did. `oapif_properties()` and `oapif_catalogue()` asked for
  a fixed number of records and returned whatever came back: today that
  is 5259 forest ranges against a ceiling of 10 000, but a collection
  growing past its ceiling would have been truncated in silence – which
  is the failure this package was written to fix, and it was in our own
  code.

- A collection whose service does not report how many features it holds
  is now paged until a page comes back short, rather than crashing. The
  missing count was handled as `NA` in three places and then passed to
  [`seq_len()`](https://rdrr.io/r/base/seq.html), which ends in
  `argument must be coercible to non-negative integer`. Some services
  really do omit it – the GDOS one does.

- [`dem_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  and
  [`ortho_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  write to `filename`, which is what every other function in the package
  calls that argument. `file` keeps working and says it has been
  renamed; it will go in a later release. Positional calls are
  unaffected – the new name sits where the old one did.

- Tests reach the functions people actually type. Fourteen of the
  exported functions had no test calling them at all, which is
  unavoidable for the ones that need the network but was not for
  [`is_aoi()`](https://igorpawelec.github.io/rgeopl/reference/as_aoi.md),
  [`aoi_geom()`](https://igorpawelec.github.io/rgeopl/reference/aoi_geom.md),
  [`cache_info()`](https://igorpawelec.github.io/rgeopl/reference/cache_info.md),
  [`cache_set_dir()`](https://igorpawelec.github.io/rgeopl/reference/cache_dir.md)
  and
  [`plot_units()`](https://igorpawelec.github.io/rgeopl/reference/plot_units.md).
  When `format` was added to
  [`dem_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  and every later argument shifted one place, nothing in the suite
  noticed.

- `gp_xml()` is gone, and `xml2` with it. It was the one function in the
  package nobody called, left over from reading coverage descriptions by
  hand, and it was the only reason for that dependency.

- The help page shared by
  [`dem_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md),
  [`pointcloud_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  and
  [`ortho_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  now says that the last of them takes no `format`: its index has no
  such column, because orthophoto sheets are published one way.

## rgeopl 0.4.0

- [`pointcloud_get()`](https://igorpawelec.github.io/rgeopl/reference/pointcloud_get.md)
  carries the point cloud chain as far as it can go without leaving CRAN
  behind: it downloads what an index points at, checks the selection is
  one survey, and returns the files with the coordinate system the
  archive says they are in. That last part is the reason it exists. Read
  straight out of the LAS headers, a 2024 tile declares EPSG:2180 while
  the 2012 and 2014 tiles carry a projection record three bytes long,
  which is to say empty – and a catalogue with no coordinate system is
  the kind of thing that goes unnoticed until an overlay lands in the
  wrong place.

  It stops one line short of a `lidR` catalogue on purpose. `lidR` was
  archived from CRAN on 2026-06-09 together with `rlas`, and there is no
  way to reach it that leaves a check clean: naming it in `Suggests` or
  in `Enhances` makes dependency resolution fetch it from a repository
  that no longer carries it and fail, while calling
  [`requireNamespace()`](https://rdrr.io/r/base/ns-load.html) without
  declaring it raises a check WARNING. All three measured, the last one
  on four platforms at once.
  [`?pointcloud_get`](https://igorpawelec.github.io/rgeopl/reference/pointcloud_get.md)
  gives the line to write, and where `lidR` still installs from.

- [`chm_get()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  takes a `year`. Without one it uses the coverage services as before,
  which publish the current model and nothing else; with one it
  assembles the model from archive tiles, which is the only route to an
  earlier flight and the route people were walking by hand.
  [`chm_years()`](https://igorpawelec.github.io/rgeopl/reference/chm_years.md)
  lists the vintages an area can make a canopy model from at all – not
  many can, because the terrain has been remapped far more often than
  the surface.

- [`dem_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  and
  [`pointcloud_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  take a `format`. The service publishes one map sheet in several forms
  at once – measured across three distant areas, 178 of 1028
  sheet/product/vintage combinations come in more than one, and some in
  three – and only `"grid"` is a raster. The others are text lists of
  points and triangulated models, which look like extra tiles until
  something downstream refuses them.

- Tiles are joined through a GDAL virtual raster instead of being read
  into memory one by one. Measured on 15 orthophoto tiles, 586 MB, cut
  to an 800 m square: **175 s before, 0.8 s after**, with not one cell
  of 17.3 million differing. On 15 elevation tiles the same cut went
  from 13.2 s to 0.6 s. The old path also materialised the whole join
  before cropping it, which for those orthophoto tiles meant asking the
  disk for 17 GB of uncompressed scratch space – enough to fail
  outright, which is how this was found.

- The cache manifest is read once per batch and written once per batch,
  rather than once per file. It is a single table for the whole cache
  and it only grows, so the old way got slower the longer the package
  was used: a 1336-tile job spent 10 s on bookkeeping with 1500 rows in
  the manifest and **125 s with 50 000**. Both now take under a fifth of
  a second.

- Single downloads stream to disk instead of being assembled in memory
  first, which is what the parallel path already did. A point cloud tile
  no longer costs its own size in RAM before it reaches the cache.

- [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md)
  refuses a selection that mixes file formats, and says so. Every
  elevation sheet is published twice under one sheet number, as a grid
  and as a list of points; picking both was previously reported as a
  duplicate sheet, and the advice given for that case did not help.

## rgeopl 0.3.0

- A URL repeated inside one selection is now fetched once. Two rows
  pointing at the same file resolved to the same target path, so both
  transfers wrote to one temporary file and raced each other. Every row
  still gets its path back; only the transfer is shared.
- [`ortho_stack()`](https://igorpawelec.github.io/rgeopl/reference/ortho_stack.md)
  joins the CIR and RGB products of one flight into a single four-band
  raster: near-infrared, red, green, blue.
  [`ortho_pairs()`](https://igorpawelec.github.io/rgeopl/reference/ortho_pairs.md)
  lists the vintages that publish both, which is the question it raises.
  Measured before building it, on one sheet at 0.25 m: CIR’s red and
  green correlate with RGB’s at **0.999**, and its first band with
  nothing in RGB (0.19 to 0.47). The two products are one radiometric
  result cut two ways, so stacking them is sound – and blue is the only
  band RGB actually contributes. A vegetation index therefore wants
  `bands = "cir"`, which halves the download: infrared and red already
  sit in one file, consistent with each other.
- [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md)
  gains `max_active`, so a stack can pass its connection limit down to
  the downloads.
- `mask` now works on the coverage side too:
  [`dem_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md),
  [`ortho_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  and
  [`chm_get()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  take it, and
  [`chm_build()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  takes an `aoi` to go with it. The coverage services are addressed by a
  bounding box, so until now a ragged stand came back through this path
  with its corners filled in while the same request through
  [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md)
  came back cut to the outline. One word should not mean two things
  depending on which way the data was fetched.

## rgeopl 0.2.0

### Many areas at once

Asking about hundreds of scattered plots used to mean asking about the
country. The bounding box drawn around 40 plots of 500 m radius covers
291 081 km2 against their own 31 km2, and the elevation index answered
it with 1 410 846 records – 936 times what the plots needed, assembled
over tens of minutes and then thrown away.

- [`dem_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md),
  [`ortho_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  and
  [`pointcloud_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  gain `by_feature`. Scattered areas are now asked about one feature at
  a time and the answers merged, with duplicate map sheets dropped. The
  default, `NULL`, decides by comparing the box around everything with
  the sum of the boxes around each part, so a single area or a tight
  cluster still goes out as one request.
- Those queries run concurrently, and so do downloads: `max_active`,
  defaulting to `getOption("rgeopl.max_active", 6)` and capped at 16.
- Measured on the same 40 plots: **1336 tiles in 7.2 s**, and 0.49 s on
  a second run, because each feature’s answer is cached separately.
- Concurrency is
  [`httr2::req_perform_parallel()`](https://httr2.r-lib.org/reference/req_perform_parallel.html)
  – parallel I/O from one R process, not parallel R. That is deliberate:
  the download manifest is a read-modify-write of one file, and it stays
  correct only because the bookkeeping still runs on a single thread.
  The same work under multisession workers would race on that file and
  lose records without any error.
- Index queries now refuse a bounding box holding more than
  `max_records` (default 200 000) rather than grinding through it, and
  say to try `by_feature = TRUE`.
- A tile that fails to download leaves `NA` in `path` and a warning,
  instead of abandoning the rest of the batch.

## rgeopl 0.1.0

First release. One area of interest, handed to every Polish national
geodata service in the form it expects, with server limits handled and
everything cached.

### Areas of interest

- [`as_aoi()`](https://igorpawelec.github.io/rgeopl/reference/as_aoi.md)
  takes an `sf`, `sfc` or `sfg` object, an `sf` bounding box, a `terra`
  `SpatVector`, `SpatRaster` or `SpatExtent`, a point or bounding box as
  bare numbers, a coordinate matrix, a file path, or WKT. For bare
  numbers the CRS is inferred from the coordinate range – Poland’s
  longitude/latitude window and the PL-1992 window do not overlap – or
  the call fails rather than guessing.
- [`aoi_bbox()`](https://igorpawelec.github.io/rgeopl/reference/aoi_geom.md)
  and
  [`aoi_geom()`](https://igorpawelec.github.io/rgeopl/reference/aoi_geom.md)
  hand it on in whichever CRS a service needs.
- [`rgeopl_example()`](https://igorpawelec.github.io/rgeopl/reference/rgeopl_example.md)
  ships two real areas to experiment on: a point in a pine stand in
  Warmia, and a 600 ha survey area near Gniezno.

### What data exist: the GUGiK indexes

- [`dem_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md),
  [`ortho_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  and
  [`pointcloud_request()`](https://igorpawelec.github.io/rgeopl/reference/dem_request.md)
  return one row per tile, with vintage, format, download link and the
  tile outline as geometry. Column names follow `rgugik`, so existing
  scripts port with a rename of the function call.
- The 1000-record ceiling on the underlying service is handled
  internally: the count is read first, and beyond one page the results
  are assembled by object id. A 40 x 40 km area returns 19 766 records
  in 20 requests, and a short result raises rather than passing as
  complete.
- [`coverage()`](https://igorpawelec.github.io/rgeopl/reference/coverage.md)
  reports how much of the area each vintage actually covers, and
  [`plot_coverage()`](https://igorpawelec.github.io/rgeopl/reference/coverage.md)
  draws it as small multiples, one panel per vintage.
- [`tile_download()`](https://igorpawelec.github.io/rgeopl/reference/tile_download.md)
  fetches what survives your filtering;
  [`tile_mosaic()`](https://igorpawelec.github.io/rgeopl/reference/tile_mosaic.md)
  joins the tiles, cropping and masking to the area on request.

### Ready-made rasters: the GUGiK coverages

- [`dem_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  and
  [`ortho_get()`](https://igorpawelec.github.io/rgeopl/reference/dem_get.md)
  return the current model clipped to the area, with no tiles to mosaic.
  ASCII grids are converted to GeoTIFF by default, which is lossless and
  about a quarter of the size.
- [`chm_get()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  and
  [`chm_build()`](https://igorpawelec.github.io/rgeopl/reference/chm_get.md)
  produce a canopy height model, refusing to subtract two rasters that
  are not on the same grid.
- [`open_raster()`](https://igorpawelec.github.io/rgeopl/reference/open_raster.md)
  attaches the coordinate system that ASCII grids do not carry.

### Forest Data Bank

- [`bdl_directorates()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md),
  [`bdl_inspectorates()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md),
  [`bdl_ranges()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md),
  [`bdl_subareas()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md)
  and
  [`bdl_compartments()`](https://igorpawelec.github.io/rgeopl/reference/bdl_directorates.md)
  return the State Forests hierarchy for an area. Compartments are not
  published as vectors and are derived from the forest address.
- [`bdl_unit()`](https://igorpawelec.github.io/rgeopl/reference/bdl_unit.md)
  finds a unit by name, ignoring case and Polish diacritics;
  [`bdl_by_address()`](https://igorpawelec.github.io/rgeopl/reference/bdl_by_address.md)
  finds one by forest address at any depth, from a regional directorate
  down to a single subarea.
- [`bdl_catalogue()`](https://igorpawelec.github.io/rgeopl/reference/bdl_catalogue.md)
  and
  [`bdl_overview()`](https://igorpawelec.github.io/rgeopl/reference/bdl_overview.md)
  list the whole country: 17 regional directorates, 429 forest
  inspectorates, 5259 forest ranges.
- [`parse_forest_address()`](https://igorpawelec.github.io/rgeopl/reference/parse_forest_address.md)
  splits the address into its seven fields.

### Administrative boundaries

- [`prg_boundaries()`](https://igorpawelec.github.io/rgeopl/reference/prg_boundaries.md)
  returns boundaries from the State Register of Borders for an area,
  filtered by the service rather than downloaded nationally and clipped.
  Nine levels, from the state border down to cadastral districts, plus
  the State Forests units as the border register holds them.

### Cache, progress and connections

- Index responses expire on a time-to-live; downloads are kept
  permanently and recorded, so a tile already on disk is never fetched
  twice.
  [`cache_dir()`](https://igorpawelec.github.io/rgeopl/reference/cache_dir.md),
  [`cache_info()`](https://igorpawelec.github.io/rgeopl/reference/cache_info.md)
  and
  [`cache_clear()`](https://igorpawelec.github.io/rgeopl/reference/cache_info.md)
  manage it.
- Progress bars for index assembly, multi-file downloads and single
  large files. `options(rgeopl.progress = FALSE)` turns them off.
- Index queries and downloads have separate timeouts, because one should
  fail fast and the other legitimately takes minutes.

### Notes on the services, measured rather than assumed

These shaped the package and are worth knowing whether or not you use
it.

- **The GUGiK services refuse connections from outside Poland.** The
  Forest Data Bank does not.
- **`returnIdsOnly` is not subject to the 1000-record cap**, which is
  how the index is assembled completely: one request returns all 1 637
  675 object ids for the country.
- **The ArcGIS GeoJSON writer silently omits fields** of type
  `esriFieldTypeSingle`. On the orthophoto index that is the pixel size,
  which vanished with no error anywhere. Esri JSON is used instead.
- **One index field carries two units**: `char_przestrz` holds a grid
  spacing for rasters and a point density for point clouds, so they are
  split into `resolution` and `density`.
- **Acquisition dates are midnight UTC** and fall a day early when read
  in a local time zone west of Greenwich.
- **The Forest Data Bank stops offering
  [`next`](https://rdrr.io/r/base/Control.html) links after the second
  page** while still holding thousands of features, so paging is driven
  by explicit offsets against the total from the first request.
- **The border register reads a bounding box northing first**, in both
  CRS notations, and querying with the usual order returns a different
  part of the country without error.
- **A forest range’s outline is not the set of subareas addressed to
  it.** Measured on one range: 144 subareas carry its address, 194 fall
  inside its polygon.
- **`a_year` in the Forest Data Bank is an edition stamp**, identical
  across the country, not the year a management plan was revised. There
  is no archive and no vintage to filter on.
- **Coverage measures map sheet outlines, not the imagery inside them.**
  A sheet that exists but is not filled still counts, so a coverage
  share of 1 does not guarantee a mosaic without holes; `isFilled` is a
  separate question.
