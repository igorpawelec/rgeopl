# A runnable tour of the coverage services. Needs a connection, and a VPN
# endpoint in Poland: the GUGiK services refuse foreign traffic.
#
#   source(system.file("examples/wcs-demo.R", package = "rgeopl"))

library(rgeopl)

# Put the cache somewhere with room; rasters add up quickly.
# cache_set_dir("D:/geodata/cache")

area <- as_aoi(c(16.80, 52.44), buffer = 400)      # a point and a radius, in metres

terrain_file <- dem_get(area, product = "dtm", resolution = 1)
surface_file <- dem_get(area, product = "dsm", resolution = 1)
photo_file   <- ortho_get(area, product = "high", resolution = 0.5)

terrain <- open_raster(terrain_file)   # stamps EPSG:2180 on the ASCII grids,
surface <- open_raster(surface_file)   # which carry no projection of their own
photo   <- open_raster(photo_file)

canopy_height <- surface - terrain

cat("canopy heights:", round(range(terra::values(canopy_height), na.rm = TRUE), 1),
    "m\n")

op <- par(mfrow = c(1, 3), mar = c(2, 2, 3, 4.5))
terra::plotRGB(photo, stretch = "lin", mar = c(2, 2, 3, 4.5))
title(main = "orthophoto")
terra::plot(terrain, main = "terrain (NMT)")
terra::plot(canopy_height, main = "canopy height (NMPT - NMT)")
par(op)

# The other datum, and the size guard:
terrain_kron <- dem_get(area, product = "dtm", datum = "kron86")   # GeoTIFF
try(dem_get(as_aoi(c(16.80, 52.44), buffer = 20000), "dtm", resolution = 1))

# Point clouds are not coverages. For LAS and LAZ, go through the index:
clouds <- pointcloud_request(area)
head(sf::st_drop_geometry(clouds)[, c("year", "date", "format", "density")])
