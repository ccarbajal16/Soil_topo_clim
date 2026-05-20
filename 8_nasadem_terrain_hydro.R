# 8_nasadem_terrain_hydro.R
# Extract terrain and hydrological covariates from NASADEM tiles for four
# Peruvian basins: Huaral, Mantaro, Pativilca, and Tarma.
#
# Workflow:
#   1. Load four NASADEM tiles and mosaic into a single raster
#   2. Reproject mosaic to UTM Zone 18S (EPSG:32718)
#   3. Terrain covariates  – terra + whitebox
#   4. Hydrological covariates – whitebox
#   5. Visualize and export results
#
# Expected inputs  : geodata/nasadem/nasadem_{huaral,mantaro,pativilca,tarma}.tif
# Outputs          : outputs/nasadem/

library(terra)
library(whitebox)
library(sf)
library(ggplot2)
library(patchwork)
library(tidyterra)

# Initialize WhiteboxTools (run install_whitebox() once if not yet installed)
# whitebox::install_whitebox()
whitebox::wbt_init()

# Create output directory
dir.create("outputs/nasadem", showWarnings = FALSE, recursive = TRUE)

# ── 1. Load and mosaic NASADEM tiles ─────────────────────────────────────────

nasadem_files <- c(
  huaral    = "geodata/nasadem/nasadem_huaral.tif",
  mantaro   = "geodata/nasadem/nasadem_mantaro.tif",
  pativilca = "geodata/nasadem/nasadem_pativilca.tif",
  tarma     = "geodata/nasadem/nasadem_tarma.tif"
)

# Verify that all files exist
missing <- nasadem_files[!file.exists(nasadem_files)]
if (length(missing) > 0) {
  stop("Missing NASADEM files:\n", paste(missing, collapse = "\n"))
}

tiles <- lapply(nasadem_files, rast)

# Mosaic all four tiles into one seamless DEM
nasadem_mosaic <- do.call(mosaic, c(tiles, list(fun = "mean")))

# Reproject to UTM Zone 18S – standard CRS for central Peru
nasadem_utm <- project(nasadem_mosaic, "EPSG:32718", method = "bilinear")
names(nasadem_utm) <- "elevation"

writeRaster(nasadem_utm,
            "outputs/nasadem/nasadem_mosaic_utm.tif",
            overwrite = TRUE)

cat("Mosaic extent :", as.character(ext(nasadem_utm)), "\n")
cat("Resolution    :", res(nasadem_utm), "m\n")

# ── 2. Terrain covariates with terra ─────────────────────────────────────────

dem_path <- "outputs/nasadem/nasadem_mosaic_utm.tif"

slope_rad  <- terrain(nasadem_utm, "slope",     unit = "radians",
                      filename = "outputs/nasadem/slope_radians.tif",   overwrite = TRUE)
slope_deg  <- terrain(nasadem_utm, "slope",     unit = "degrees",
                      filename = "outputs/nasadem/slope_degrees.tif",   overwrite = TRUE)
aspect     <- terrain(nasadem_utm, "aspect",    unit = "degrees",
                      filename = "outputs/nasadem/aspect_degrees.tif",  overwrite = TRUE)
tpi        <- terrain(nasadem_utm, "TPI",
                      filename = "outputs/nasadem/tpi.tif",             overwrite = TRUE)
tri        <- terrain(nasadem_utm, "TRI",
                      filename = "outputs/nasadem/tri.tif",             overwrite = TRUE)
roughness  <- terrain(nasadem_utm, "roughness",
                      filename = "outputs/nasadem/roughness.tif",       overwrite = TRUE)
hillshade  <- shade(slope_rad, aspect,
                    angle = 45, direction = 315,
                    filename = "outputs/nasadem/hillshade.tif",         overwrite = TRUE)

# Northness and Eastness – linearise circular aspect for regression models
aspect_rad <- aspect * (pi / 180)
northness  <- cos(aspect_rad)
eastness   <- sin(aspect_rad)
names(northness) <- "northness"
names(eastness)  <- "eastness"
writeRaster(northness, "outputs/nasadem/northness.tif", overwrite = TRUE)
writeRaster(eastness,  "outputs/nasadem/eastness.tif",  overwrite = TRUE)

# ── 3. Additional terrain covariates with whitebox ───────────────────────────

wbt_profile_curvature(
  dem    = dem_path,
  output = "outputs/nasadem/curvature_profile.tif"
)

wbt_plan_curvature(
  dem    = dem_path,
  output = "outputs/nasadem/curvature_plan.tif"
)

wbt_tangential_curvature(
  dem    = dem_path,
  output = "outputs/nasadem/curvature_tangential.tif"
)

wbt_total_curvature(
  dem    = dem_path,
  output = "outputs/nasadem/curvature_total.tif"
)

wbt_multiscale_topographic_position_index(
  dem      = dem_path,
  output   = "outputs/nasadem/multiscale_tpi.tif",
  min_scale = 1,
  step      = 5,
  num_steps = 10
)

# ── 4. Hydrological covariates with whitebox ─────────────────────────────────

# 4.1 Depression removal (required before flow routing)
wbt_breach_depressions_least_cost(
  dem    = dem_path,
  output = "outputs/nasadem/dem_breached.tif",
  dist   = 10,
  fill   = TRUE
)

wbt_fill_depressions(
  dem    = "outputs/nasadem/dem_breached.tif",
  output = "outputs/nasadem/dem_filled.tif"
)

filled_path <- "outputs/nasadem/dem_filled.tif"

# 4.2 D8 flow routing
wbt_d8_pointer(
  dem    = filled_path,
  output = "outputs/nasadem/d8_flow_dir.tif"
)

wbt_d8_flow_accumulation(
  input    = filled_path,
  output   = "outputs/nasadem/d8_flow_acc.tif",
  out_type = "cells"
)

# 4.3 D-infinity flow routing (Specific Contributing Area for TWI)
wbt_d_inf_flow_accumulation(
  input    = filled_path,
  output   = "outputs/nasadem/dinf_sca.tif",
  out_type = "Specific Contributing Area"
)

# 4.4 Topographic Wetness Index (TWI)
wbt_slope(
  dem    = filled_path,
  output = "outputs/nasadem/slope_filled_deg.tif",
  units  = "degrees"
)

wbt_wetness_index(
  sca    = "outputs/nasadem/dinf_sca.tif",
  slope  = "outputs/nasadem/slope_filled_deg.tif",
  output = "outputs/nasadem/twi.tif"
)

# 4.5 LS-Factor (erosion modelling support)
wbt_ls_factor(
  flow_accum = "outputs/nasadem/d8_flow_acc.tif",
  slope      = "outputs/nasadem/slope_filled_deg.tif",
  output     = "outputs/nasadem/ls_factor.tif"
)

# 4.6 Stream network – threshold = 1 000 cells (~0.9 km² at 30 m)
wbt_extract_streams(
  flow_accum = "outputs/nasadem/d8_flow_acc.tif",
  output     = "outputs/nasadem/streams.tif",
  threshold  = 1000
)

wbt_strahler_stream_order(
  d8_pntr = "outputs/nasadem/d8_flow_dir.tif",
  streams = "outputs/nasadem/streams.tif",
  output  = "outputs/nasadem/strahler_order.tif"
)

# 4.7 Vertical distance to channel network
wbt_elevation_above_stream(
  dem     = filled_path,
  streams = "outputs/nasadem/streams.tif",
  output  = "outputs/nasadem/elev_above_stream.tif"
)

# 4.8 Valley depth
wbt_valley_depth(
  dem    = filled_path,
  output = "outputs/nasadem/valley_depth.tif"
)

# ── 5. Assemble a multi-band covariate stack ──────────────────────────────────

covariate_files <- c(
  "outputs/nasadem/nasadem_mosaic_utm.tif",
  "outputs/nasadem/slope_degrees.tif",
  "outputs/nasadem/aspect_degrees.tif",
  "outputs/nasadem/hillshade.tif",
  "outputs/nasadem/tpi.tif",
  "outputs/nasadem/tri.tif",
  "outputs/nasadem/roughness.tif",
  "outputs/nasadem/northness.tif",
  "outputs/nasadem/eastness.tif",
  "outputs/nasadem/curvature_profile.tif",
  "outputs/nasadem/curvature_plan.tif",
  "outputs/nasadem/curvature_tangential.tif",
  "outputs/nasadem/twi.tif",
  "outputs/nasadem/d8_flow_acc.tif",
  "outputs/nasadem/dinf_sca.tif",
  "outputs/nasadem/ls_factor.tif",
  "outputs/nasadem/elev_above_stream.tif",
  "outputs/nasadem/valley_depth.tif"
)

covariate_stack <- rast(covariate_files)
names(covariate_stack) <- c(
  "elevation", "slope", "aspect", "hillshade",
  "tpi", "tri", "roughness", "northness", "eastness",
  "curv_profile", "curv_plan", "curv_tangential",
  "twi", "flow_acc_d8", "sca_dinf", "ls_factor",
  "elev_above_stream", "valley_depth"
)

writeRaster(covariate_stack,
            "outputs/nasadem/nasadem_covariate_stack.tif",
            overwrite = TRUE)

cat("Covariate stack saved:", nlyr(covariate_stack), "layers\n")
print(names(covariate_stack))

# ── 6. Visualization ──────────────────────────────────────────────────────────

plot_layer <- function(r, title, palette = "viridis") {
  df <- as.data.frame(r, xy = TRUE)
  val_col <- names(df)[3]
  ggplot(df, aes(x = x, y = y, fill = .data[[val_col]])) +
    geom_raster() +
    scale_fill_viridis_c(option = palette, na.value = "transparent") +
    labs(title = title, x = NULL, y = NULL) +
    theme_minimal() +
    theme(legend.position   = "none",
          axis.text         = element_blank(),
          plot.title        = element_text(size = 9, face = "bold"))
}

# Terrain panel
terrain_plots <- list(
  plot_layer(covariate_stack[["elevation"]],   "Elevation (m)",      "magma"),
  plot_layer(covariate_stack[["slope"]],        "Slope (°)",          "inferno"),
  plot_layer(covariate_stack[["aspect"]],       "Aspect (°)",         "plasma"),
  plot_layer(covariate_stack[["hillshade"]],    "Hillshade",          "Greys"),
  plot_layer(covariate_stack[["tpi"]],          "TPI",                "RdBu"),
  plot_layer(covariate_stack[["tri"]],          "TRI",                "YlOrRd"),
  plot_layer(covariate_stack[["roughness"]],    "Roughness",          "viridis"),
  plot_layer(covariate_stack[["northness"]],    "Northness",          "RdBu"),
  plot_layer(covariate_stack[["eastness"]],     "Eastness",           "RdBu")
)

terrain_panel <- wrap_plots(terrain_plots, ncol = 3) +
  plot_annotation(
    title    = "NASADEM – Terrain Covariates",
    subtitle = "Basins: Huaral · Mantaro · Pativilca · Tarma",
    theme    = theme(plot.title    = element_text(hjust = 0.5, size = 14, face = "bold"),
                     plot.subtitle = element_text(hjust = 0.5, size = 10))
  )

ggsave("outputs/nasadem/terrain_covariates.png",
       terrain_panel, width = 14, height = 14, dpi = 150)

# Hydrological panel
hydro_plots <- list(
  plot_layer(covariate_stack[["twi"]],              "TWI",                  "Blues"),
  plot_layer(log1p(covariate_stack[["flow_acc_d8"]]), "log(D8 Flow Acc.)",   "viridis"),
  plot_layer(log1p(covariate_stack[["sca_dinf"]]),  "log(Dinf SCA)",        "viridis"),
  plot_layer(covariate_stack[["ls_factor"]],        "LS Factor",            "YlOrRd"),
  plot_layer(covariate_stack[["elev_above_stream"]], "Elev. above Stream", "magma"),
  plot_layer(covariate_stack[["valley_depth"]],     "Valley Depth",         "Blues")
)

hydro_panel <- wrap_plots(hydro_plots, ncol = 3) +
  plot_annotation(
    title    = "NASADEM – Hydrological Covariates",
    subtitle = "Basins: Huaral · Mantaro · Pativilca · Tarma",
    theme    = theme(plot.title    = element_text(hjust = 0.5, size = 14, face = "bold"),
                     plot.subtitle = element_text(hjust = 0.5, size = 10))
  )

ggsave("outputs/nasadem/hydro_covariates.png",
       hydro_panel, width = 14, height = 10, dpi = 150)

print(terrain_panel)
print(hydro_panel)

cat("\nDone. All outputs in outputs/nasadem/\n")
