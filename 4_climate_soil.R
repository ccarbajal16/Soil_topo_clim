library(terra)
library(sf)
library(geodata)


### Download WorldClim data

options(geodata_default_path = "./geodata")

climper1 <- worldclim_country("Peru", var="tavg", res= 2.5, geodata_path(), version="2.1" )

climper2 <- worldclim_tile(var="prec", lon = -73.96572351, lat = -12.97525624, res= 2.5, geodata_path(), version="2.1" )

# Cropping the raster with the extension of the DEM

dem_srtm90 <- rast('outputs/dem_srtm90_torobamba.tif')

geo_crs <- "EPSG:4326"

# Assig projection to the raster
crs(dem_srtm90) <- geo_crs

# Crop the raster with the extension
climper1_crop <- crop(climper1, dem_srtm90)
climper2_crop <- crop(climper2, dem_srtm90)

# mask the raster with a polygon shapefile
torobamba <- st_read("data/borde_torobamba_geo.shp")

climper1_masked <- mask(climper1_crop, torobamba)
climper2_masked <- mask(climper2_crop, torobamba)

writeRaster(climper1_masked, "outputs/tavg_torobamba_masked.tif", overwrite = TRUE)
writeRaster(climper2_masked, "outputs/prec_torobamba_masked.tif", overwrite = TRUE)

# Download soil data from SoilGrids
clay_soilgrids <- soil_world(var="clay", depth = 30, stat = "mean",  geodata_path())

