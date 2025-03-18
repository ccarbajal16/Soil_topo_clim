# 1. Setup and configuration
library(terra) # used for terrain analysis
library(sf) # used for shapefile handling
library(elevatr) # used for elevation extraction
library(ggplot2) # used for visualization
library(patchwork) # used for plot combination

# 2. Extract points elevation

# Read CSV file and convert to sf
points_sf <- read.csv('data/soils_points.csv') |>
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326)

df_elev_aws <- get_elev_point(points_sf, prj = 4326, src = "aws")

# Save the result
write.csv(df_elev_aws, "outputs/points_elevation_aws.csv", row.names = FALSE)


# 3. Download elevation data

# Define AOI from shapefile
torobamba <- st_read("data/borde_torobamba_geo.shp")

# Download the DEM data using aws
dem_aws <- get_elev_raster(torobamba, z = 10, src = "aws", clip = "locations")

plot(dem_aws)

# Save the result
writeRaster(dem_aws, "outputs/dem_aws_torobamba.tif", overwrite = TRUE)

# Download the DEM data using OpenTopography API (https://portal.opentopography.org/newUser)
dem_alos <- get_elev_raster(torobamba, src = "alos", clip = "locations") # "alos" = 30m
dem_srtm90 <- get_elev_raster(torobamba, src = "gl3", clip = "locations") # "gl3" = 90m, "gl1" = 30m 

writeRaster(dem_srtm90, "outputs/dem_srtm90_torobamba.tif", overwrite = TRUE)

# Convert RasterLayer to SpatRaster if necessary
terra_aws <- rast(dem_aws)
terra_alos <- rast(dem_alos)
terra_srtm90 <- rast(dem_srtm90)

plot(terra_aws)

# Now project the SpatRaster
dem_utm <- terra::project(terra_aws, "epsg:32718", method = "bilinear")

# Save the result
writeRaster(dem_utm, "outputs/torobamba_dem_utm.tif", overwrite = TRUE)

# 4. Terrain analysis
# options: "slope", "aspect","TPI", "TRI", "flowdir", "roughness"
slope <- terrain(dem_utm, "slope", unit = "radians", filename="outputs/slope_terra.tif")
aspect <- terrain(dem_utm, "aspect", unit = "radians", filename="outputs/aspect_terra.tif")
tpi <- terrain(dem_utm, "TPI", filename="outputs/tpi_terra.tif")
tri <- terrain(dem_utm, "TRI", filename="outputs/tri_terra.tif")
hillshade <- shade(slope, aspect, angle = 45, direction = 270, filename="outputs/hillshade_terra.tif")

# 4.1 Hydrologic analysis
flow_dir <- terrain(dem_utm, "flowdir", filename = "outputs/flow_dir_terra.tif")
flow_acc <- flowAccumulation(flow_dir, filename = "outputs/flow_acc_terra.tif")

pp <- cbind(606387, 8569491)
w <- watershed(flow_dir, pourpoint = pp, filename = "outputs/watershed_terra.tif")

# 5. Visualization
# Function to create a plot for each raster
plot_raster <- function(raster, title) {
  # Convert raster to data frame
  df <- as.data.frame(raster, xy = TRUE)
  # Get the name of the value column (it might not always be "value")
  value_col <- names(df)[3]
  
  ggplot() +
    geom_raster(data = df,
                aes(x = x, y = y, fill = .data[[value_col]])) +
    scale_fill_viridis_c() +
    labs(title = title,
    caption = title) +
    theme_minimal() +
    theme(legend.position = "none")
}

raster_list <- list(dem_utm, slope, aspect, tpi, tri, hillshade, flow_dir, flow_acc, w)

# Create a list of plots
plot_list <- lapply(seq_along(raster_list), function(i) {
  plot_raster(raster_list[[i]], names(raster_list)[i])
})

# Combine all plots
combined_plot <- wrap_plots(plot_list, ncol = 3)

# Display the combined plot
print(combined_plot)

# Save the plot if needed
ggsave("outputs/raster_terra_comparison.png", combined_plot, width = 12, height = 8)