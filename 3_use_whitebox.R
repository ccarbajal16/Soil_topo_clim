library(terra)
library(whitebox)
library(ggplot2)
library(patchwork)

# For the first time install whitebox and initialize it
# verify if whitebox is installed:wbt_data_dir()
#whitebox::install_whitebox() 

whitebox::wbt_init() # wbt_init(exe_path = 'C:/home/user/path/to/whitebox_tools.exe')


# List of tools available in whitebox (https://www.whiteboxgeo.com/manual/wbt_book/tool_index.html)

# For terrain analysis
wbt_hillshade(dem="outputs/torobamba_dem_utm.tif", output = "outputs/hillshade_wbt.tif", azimuth = 315, altitude = 45)

hillshade_rast <- rast("outputs/hillshade_wbt.tif")

wbt_slope(dem = "outputs/torobamba_dem_utm.tif", output = "outputs/slope_wbt.tif", units = 'radians')

slope_rast <- rast("outputs/slope_wbt.tif")

# For land cover change detection

# For hydrology studies
wbt_breach_depressions_least_cost(dem = "outputs/torobamba_dem_utm.tif", output = "outputs/breach_depressions_torobamba.tif", dist = 5, fill = TRUE)

wbt_fill_depressions(dem = "outputs/breach_depressions_torobamba.tif", output = "outputs/fill_breach_torobamba.tif")

wbt_d8_flow_accumulation(input = "outputs/fill_breach_torobamba.tif",
                         output = "outputs/D8FA_torobamba.tif")

d8_wbt <- rast("outputs/D8FA_torobamba.tif")

# Calculate TWI

wbt_d_inf_flow_accumulation(input = "outputs/fill_breach_torobamba.tif",
                            output = "outputs/DinfFAsca_torobamba.tif",
                            out_type = "Specific Contributing Area")

wbt_slope(dem = "outputs/fill_breach_torobamba.tif",
          output = "outputs/slope_wbt_degrees.tif",
          units = "degrees")

wbt_wetness_index(sca = "outputs/DinfFAsca_torobamba.tif",
                  slope = "outputs/slope_wbt_degrees.tif",
                  output = "outputs/TWI_wbt.tif")

twi_wbt <- rast("outputs/TWI_wbt.tif")

# For visualization

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

raster_list <- list(hillshade_rast, slope_rast, d8_wbt, twi_wbt)

# Create a list of plots
plot_list <- lapply(seq_along(raster_list), function(i) {
  plot_raster(raster_list[[i]], names(raster_list)[i])
})

# Combine all plots
combined_plot_wbt <- wrap_plots(plot_list, ncol = 2)

# Display the combined plot
print(combined_plot_wbt)

# Save the plot if needed
ggsave("outputs/raster_wbt_comparison.png", combined_plot, width = 12, height = 8)