# Load required libraries
library(rgrass)
library(terra)
library(tidyterra) 
library(ggplot2)
library(patchwork)

# Set environment variables for PROJ before loading GRASS
# This ensures GRASS uses its own PROJ database
Sys.setenv(PROJ_LIB = file.path("C:/Program Files/GRASS GIS 8.4/share/proj"))

# Load elevation raster
elev <- rast("outputs/torobamba_dem_utm.tif")

# Initialize GRASS GIS environment
initGRASS(
  gisBase = "C:/Program Files/GRASS GIS 8.4", #The directory path to GRASS binaries
  gisDbase = "C:/Users/usuario/grassdata", #GRASS GISDBASE directory path
  home = "C:/Users/usuario", #The directory in which to create the .gisrc file
  location = "torobamba", #GRASS location directory
  mapset = "basin_torobamba", #GRASS mapset directory
  SG = elev, #Define extent and resolution of the GRASS location
  override = TRUE
)

# Verify GRASS environment and import raster with CRS override
execGRASS("g.gisenv", flags = "s") # read .grassrc file

# Convert elevation raster to GRASS format
write_RAST(elev, "elev_torobamba", flags = c("overwrite", "o"))

# List imported rasters available in the mapset
execGRASS("g.list", type = "raster", flags = "p")

## Topographic variables ##

# Generate slope and aspect maps
execGRASS("r.slope.aspect", 
          elevation = "elev_torobamba", 
          slope = "slope_torobamba",
          aspect = "aspect_torobamba")

# Export raster to GeoTIFF
execGRASS("r.out.gdal", 
          input = "aspect_torobamba", 
          output = "outputs/grass_aspect_torobamba.tif",
          format = "GTiff",
          flags = c("overwrite", "c"))

# Generate of relief map
execGRASS("r.relief", 
          input = "elev_torobamba", 
          output = "relief_map",
          altitude = 30,
          azimuth = 250,
          units = "survey",
          flags = "overwrite"
          )

# Import raster from GRASS GIS into R
topo_maps <- read_RAST(c("aspect_torobamba", "slope_torobamba", "relief_map"))

aspect <- topo_maps$aspect_torobamba
slope <- topo_maps$slope_torobamba
relief <- topo_maps$relief_map

# Export to GeoTIFF using terra
writeRaster(aspect, "outputs/grass_aspect.tif")
writeRaster(slope, "outputs/grass_slope.tif")
writeRaster(relief, "outputs/grass_relief.tif")

# Plot aspect, slope, and relief using patchwork
plot_aspect <- ggplot() +
  geom_spatraster(data = aspect) +
  scale_fill_viridis_c() +
  labs(title = "Aspect") +
  theme_minimal()
plot_slope <- ggplot() +
  geom_spatraster(data = slope) +
  scale_fill_viridis_c() +
  labs(title = "Slope") +
  theme_minimal()
plot_relief <- ggplot() +
  geom_spatraster(data = relief) +
  scale_fill_viridis_c() +
  labs(title = "Relief") +
  theme_minimal()

# Combine the three plots in a grid layout with improved spacing and annotations
combined_plot <- (plot_aspect +
                  plot_slope  +
                  plot_relief ) +
    plot_layout(ncol = 3, guides = "collect") +
    plot_annotation(
        title = "Topographic Variables",
        theme = theme(
            plot.title = element_text(hjust = 0.5, size = 16, face = "bold"),
            plot.margin = margin(10, 10, 10, 10)
        )
    ) & theme(legend.position = "none")

print(combined_plot)

## Hidrologic tools ##

# Set the region resolution to match the input map's resolution
execGRASS("g.region", raster = "elev_torobamba", flags = "p")

# Generate Topographic Wetness Index (TWI)
execGRASS("r.topidx",
          input = "elev_torobamba",
          output = "twi_map",
          flags = "overwrite")

# Calculate flow length
execGRASS("r.flow",
          elevation = "elev_torobamba",
          flowlength = "flowlength",
          flags = c("overwrite", "u"))

# Oher useful hydrological layers
# Calculate flow direction, accumulation and streams:
execGRASS("r.watershed",
          elevation = "elev_torobamba",
          accumulation = "flowacc", #Number of cells that drain through each cell
          drainage = "flowdir", #Directions numbered from 1 to 8
          threshold = 1000, #Minimum size of exterior watershed basin
          stream = "stream",
          flags = c("overwrite", "s"))

hydromaps <- read_RAST(c("twi_map", "flowlength","flowacc", "flowdir", "stream"))

twi <- hydromaps$twi_map
flow_length <- hydromaps$flowlength
flow_acc <- hydromaps$flowacc
flow_direct <- hydromaps$flowdir
streams <- hydromaps$stream

# Plot all hydrological layers using patchwork
plot_twi <- ggplot() +
    geom_spatraster(data = twi) +
    scale_fill_viridis_c() +
    labs(title = "Topographic Wetness Index (TWI)") +
    theme_minimal()

plot_flow_length <- ggplot() +
    geom_spatraster(data = flow_length) +
    scale_fill_viridis_c() +
    labs(title = "Flow Length") +
    theme_minimal()

plot_flow_acc <- ggplot() +
    geom_spatraster(data = flow_acc) +
    scale_fill_viridis_c() +
    labs(title = "Flow Accumulation") +
    theme_minimal()

plot_flow_direct <- ggplot() +
    geom_spatraster(data = flow_direct) +
    scale_fill_viridis_c() +
    labs(title = "Flow Direction") +
    theme_minimal()

plot_streams <- ggplot() +
    geom_spatraster(data = streams) +
    scale_fill_viridis_c() +
    labs(title = "Streams") +
    theme_minimal()

# Combine the plots in a grid layout
combined_hydro_plot <- (plot_twi +
                                                plot_flow_length +
                                                plot_flow_acc +
                                                plot_flow_direct +
                                                plot_streams) +
    plot_layout(ncol = 3, guides = "collect") +
    plot_annotation(
        title = "Hydrological Layers",
        theme = theme(
            plot.title = element_text(hjust = 0.5, size = 16, face = "bold"),
            plot.margin = margin(10, 10, 10, 10)
        )
    ) & theme(legend.position = "none")

print(combined_hydro_plot)

# Save the plot if needed
ggsave("outputs/hidro_maps.png", combined_hydro_plot, width = 12, height = 8)

# Export to GeoTIFF using terra
writeRaster(twi, "outputs/grass_twi.tif")
writeRaster(flow_length, "outputs/grass_flowlength.tif")
writeRaster(flow_acc, "outputs/grass_flowacc.tif")
writeRaster(flow_direct, "outputs/grass_flowdir.tif")
writeRaster(streams, "outputs/grass_stream.tif")


# Other Tools
# Generate Accumulate cost map
execGRASS("r.cost", 
          input = "slope_torobamba", 
          output = "cost_map",
          start_coordinates = c(612655.392,8563151.712),
          stop_coordinates = c(630611.054,8546311.309),
          flags = "overwrite"
          )

grass_costs <- read_RAST("cost_map")
plot(grass_costs)

# Export raster to GeoTIFF
writeRaster(grass_costs, "outputs/grass_cost.tif")

