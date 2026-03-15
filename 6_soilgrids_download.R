# =============================================================================
# Download ALL SoilGrids soil properties at 15–30 cm depth
#
# This script streams directly from the ISRIC
# SoilGrids 2.0 VRT files via /vsicurl/, giving the true 250 m native product.
# VRT URL pattern (250 m native resolution):
#   https://files.isric.org/soilgrids/latest/data/{var}/{var}_15-30cm_mean.vrt
#
# SoilGrids variables downloaded (all available at 15–30 cm, stat = "mean"):
#   var       | Full name                          | Units
#   ----------|------------------------------------|--------------------
#   bdod      | Bulk density fine earth            | kg dm⁻³  (×100 raw)
#   cec       | Cation exchange capacity           | mmol(c) kg⁻¹ (×10 raw)
#   cfvo      | Coarse fragments volume            | cm³ 100cm⁻³ (×10 raw)
#   clay      | Clay content                       | g kg⁻¹ (×10 raw)
#   nitrogen  | Total nitrogen                     | cg kg⁻¹  (×100 raw)
#   ocd       | Organic carbon density             | kg m⁻³   (×10 raw)
#   phh2o     | pH (water 1:2.5)                   | pH×10 (raw)
#   sand      | Sand content                       | g kg⁻¹ (×10 raw)
#   silt      | Silt content                       | g kg⁻¹ (×10 raw)
#   soc       | Soil organic carbon                | dg kg⁻¹  (×10 raw)
# =============================================================================

# ── 0. PACKAGES ───────────────────────────────────────────────────────────────
# Fix PROJ database conflict with PostgreSQL/PostGIS installation.
# PostgreSQL ships an old proj.db that confuses GDAL. Force terra's bundled one.
.proj_dir <- system.file("proj", package = "terra")
if (nchar(.proj_dir) > 0) {
  Sys.setenv(PROJ_LIB = .proj_dir)
  Sys.setenv(PROJ_DATA = .proj_dir)
}
rm(.proj_dir)

required <- c("terra", "sf", "tidyverse", "viridis")
new_pkgs  <- required[!(required %in% installed.packages()[, "Package"])]
if (length(new_pkgs)) install.packages(new_pkgs)
invisible(lapply(required, library, character.only = TRUE))

# Simple timestamped console logger used throughout this script.
# level: "INFO" (default), "SUCCESS", "WARNING", "ERROR"
log_msg <- function(msg, level = "INFO") {
  ts <- format(Sys.time(), "%H:%M:%S")
  cat(sprintf("[%s] [%-7s] %s\n", ts, level, msg))
}

# ── 1. CONFIGURATION ──────────────────────────────────────────────────────────
# Loading and standardizing the study-area boundary polygon (the AOI)
# from a spatial file (typically a GeoPackage).
read_boundary <- function(path) {
  b <- suppressWarnings(st_read(path, quiet = TRUE))
  if (!inherits(b, "sf")) stop("Boundary read failed: ", path)
  geom_type <- unique(as.character(st_geometry_type(b)))
  poly_types <- c("POLYGON", "MULTIPOLYGON")
  if (!any(geom_type %in% poly_types)) stop("Boundary file has no polygon geometry: ", path)
  b <- b[st_geometry_type(b) %in% poly_types, , drop = FALSE]
  b <- st_make_valid(b)
  st_union(b)
}

# Infer the appropriate UTM EPSG code from the boundary centroid.
# Used to define the output CRS for reprojection/extraction.
guess_utm_epsg <- function(boundary) {
  boundary_wgs84 <- st_transform(boundary, 4326)
  c_xy <- st_coordinates(st_centroid(boundary_wgs84))[1, ]
  lon <- c_xy[1]
  lat <- c_xy[2]
  zone <- floor((lon + 180) / 6) + 1
  if (lat >= 0) 32600 + zone else 32700 + zone
}

# Read soil sampling locations from vector files (gpkg/shp/geojson) or CSV.
# Vector inputs are assumed to already contain point geometries; CSV inputs must
# provide lon/lat columns and are interpreted as WGS84 (EPSG:4326).
# crs_out: numeric EPSG code (e.g. 32718), "EPSG:32718" string, or a crs object.
read_soil_points <- function(path, crs_out) {
  if (!file.exists(path)) stop("Soil points file not found: ", path)
  # Accept numeric EPSG → convert to "EPSG:NNNNN" for st_transform
  if (is.numeric(crs_out)) crs_out <- paste0("EPSG:", crs_out)
  ext <- tolower(tools::file_ext(path))
  if (ext %in% c("gpkg", "shp", "geojson")) {
    pts <- suppressWarnings(st_read(path, quiet = TRUE))
    if (!inherits(pts, "sf")) stop("Soil points read failed: ", path)
    pts <- st_transform(pts, crs_out)
    return(pts)
  }
  if (ext %in% c("csv", "txt")) {
    df <- readr::read_csv(path, show_col_types = FALSE)
    nms <- names(df)
    lon_col <- nms[match(TRUE, tolower(nms) %in% c("lon", "long", "longitude"))]
    lat_col <- nms[match(TRUE, tolower(nms) %in% c("lat", "latitude"))]
    if (is.na(lon_col) || is.na(lat_col)) {
      stop("Soil CSV must contain lon/lat columns (e.g., LONG/LAT, lon/lat): ", path)
    }
    pts <- st_as_sf(df, coords = c(lon_col, lat_col), crs = 4326)
    pts <- st_transform(pts, crs_out)
    return(pts)
  }
  stop("Unsupported soil points file type: ", path)
}

# Generate output directories for data and figures, if they don't already exist.
DATA_DIR <- "data"
OUT_DIR <- "data/soilgrids_250m"
OUT_FIG <- "figures"

make_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE)
}

make_dir(OUT_DIR)
make_dir(OUT_FIG)

# ISRIC SoilGrids 2.0 VRT base URL (250 m native resolution, Homolosine CRS)
ISRIC_BASE <- "https://files.isric.org/soilgrids/latest/data"

# Depth layer string as used in ISRIC filenames
DEPTH_LAYER <- "15-30cm"

# All SoilGrids variables available at 15–30 cm
VARIABLES <- c(
  "bdod",      # Bulk density of fine earth      kg dm⁻³  ×100
  "cec",       # Cation exchange capacity         mmol(c) kg⁻¹  ×10
  "cfvo",      # Coarse fragments volumetric      cm³ 100cm⁻³  ×10
  "clay",      # Clay content                     g kg⁻¹  ×10
  "nitrogen",  # Total nitrogen                   cg kg⁻¹  ×100
  "ocd",       # Organic carbon density           kg m⁻³  ×10
  "phh2o",     # pH water                         pH×10
  "sand",      # Sand content                     g kg⁻¹  ×10
  "silt",      # Silt content                     g kg⁻¹  ×10
  "soc"        # Soil organic carbon              dg kg⁻¹  ×10
  # "ocs"  excluded: only available as 0–30 cm cumulative stock
  # "wrb"  excluded: categorical WRB classification, not numeric
)

# Scaling factors to convert raw integer values to physical units
# raw_value / factor = physical unit value
CONVERSION_FACTORS <- c(
  bdod     = 100,   # → kg dm⁻³
  cec      = 10,    # → mmol(c) kg⁻¹
  cfvo     = 10,    # → cm³ 100cm⁻³
  clay     = 10,    # → g kg⁻¹
  nitrogen = 100,   # → g kg⁻¹
  ocd      = 10,    # → kg m⁻³
  phh2o    = 10,    # → pH
  sand     = 10,    # → g kg⁻¹
  silt     = 10,    # → g kg⁻¹
  soc      = 10     # → dg kg⁻¹
)

# Human-readable labels for maps and tables (physical units after conversion)
VAR_LABELS <- c(
  bdod     = "Bulk density (kg dm\u207b\u00b3)",
  cec      = "CEC (mmol(c) kg\u207b\u00b9)",
  cfvo     = "Coarse fragments (cm\u00b3 100cm\u207b\u00b3)",
  clay     = "Clay (g kg\u207b\u00b9)",
  nitrogen = "Total N (g kg\u207b\u00b9)",
  ocd      = "OC density (kg m\u207b\u00b3)",
  phh2o    = "pH (water)",
  sand     = "Sand (g kg\u207b\u00b9)",
  silt     = "Silt (g kg\u207b\u00b9)",
  soc      = "SOC (g kg\u207b\u00b9)"
)

# ── 2. DOWNLOAD (VSI streaming at 250 m) ──────────────────────────────────────
# terra::rast("/vsicurl/<url>") opens the remote VRT without downloading the
# full global file. crop() fetches only the bytes covering the study area.

boundary <- read_boundary(file.path(DATA_DIR, "borde_poly.gpkg"))
CRS_UTM  <- guess_utm_epsg(boundary)
log_msg(sprintf("Output CRS (UTM) : EPSG:%s", CRS_UTM))

soil_rasters <- list()

log_msg(sprintf(
  "Streaming %d SoilGrids variables at %s, 250 m native resolution",
  length(VARIABLES), DEPTH_LAYER
))

for (var in VARIABLES) {

  out_file <- file.path(OUT_DIR,
                        sprintf("soilgrids_%s_%s.tif", var, DEPTH_LAYER))

  # Load from cache if already downloaded
  if (file.exists(out_file)) {
    log_msg(sprintf("%-10s cached — loading from disk", var))
    soil_rasters[[var]] <- rast(out_file)
    next
  }

  vrt_url <- sprintf("%s/%s/%s_%s_mean.vrt", ISRIC_BASE, var, var, DEPTH_LAYER)

  log_msg(sprintf("%-10s streaming from ISRIC VRT...", var))

  tryCatch({

    # Open remote VRT via GDAL /vsicurl/ driver (Homolosine CRS)
    soil_global <- rast(paste0("/vsicurl/", vrt_url))

    # Reproject the boundary polygon to the raster's native Homolosine CRS,
    # then crop to that extent. terra::project() requires a SpatVector, not
    # an sf bbox, so we convert the boundary sfc → SpatVector first.
    aoi_vect     <- vect(st_as_sf(boundary))
    aoi_native   <- project(aoi_vect, crs(soil_global))
    soil_cropped <- crop(soil_global, aoi_native)

    if (is.null(soil_cropped) || ncell(soil_cropped) == 0)
      stop("Cropped raster is empty — verify BBOX coordinates")

    # Report raw range
    v_min <- global(soil_cropped, "min", na.rm = TRUE)[1, 1]
    v_max <- global(soil_cropped, "max", na.rm = TRUE)[1, 1]
    fac   <- CONVERSION_FACTORS[[var]]
    log_msg(sprintf(
      "%-10s raw range: %.0f – %.0f  (physical: %.3f – %.3f)",
      var, v_min, v_max, v_min / fac, v_max / fac
    ))

    # Scale to physical units before saving
    soil_scaled        <- soil_cropped / fac
    names(soil_scaled) <- var

    writeRaster(soil_scaled, out_file, overwrite = TRUE)
    log_msg(sprintf("%-10s saved  → %s", var, out_file), "SUCCESS")
    soil_rasters[[var]] <- soil_scaled

  }, error = function(e) {
    log_msg(sprintf("%-10s FAILED: %s", var, e$message), "ERROR")
  })
}

n_ok <- length(soil_rasters)
log_msg(sprintf("Download complete: %d / %d variables OK",
                n_ok, length(VARIABLES)),
        if (n_ok == length(VARIABLES)) "SUCCESS" else "WARNING")

if (n_ok == 0) stop("No rasters downloaded. Check network/VRT access.")

# ── 3. BUILD UTM STACK ────────────────────────────────────────────────────────
# Reproject from WGS84 (250 m) to UTM
# Pixel size after reprojection is kept at 250 m (native SoilGrids resolution).

log_msg("Reprojecting to UTM and assembling multi-band stack...")

utm_layers <- lapply(names(soil_rasters), function(v) {
  r <- project(soil_rasters[[v]],
               paste0("EPSG:", CRS_UTM),
               method = "bilinear",
               res    = 250)          # native 250 m resolution
  names(r) <- v
  r
})

# Align all layers to the first one (same extent/resolution)
template     <- utm_layers[[1]]
utm_aligned  <- lapply(utm_layers, function(r) resample(r, template,
                                                         method = "bilinear"))
sg_stack_utm <- do.call(c, utm_aligned)
names(sg_stack_utm) <- names(soil_rasters)

stack_file <- file.path(OUT_DIR, "soilgrids_stack_utm.tif")
writeRaster(sg_stack_utm, stack_file, overwrite = TRUE)
log_msg(sprintf("UTM stack (%d bands, 250 m) saved → %s",
                nlyr(sg_stack_utm), stack_file), "SUCCESS")

cat("\nStack summary:\n")
print(sg_stack_utm)

# ── 4. EXTRACT VALUES AT SOIL PROFILE LOCATIONS ───────────────────────────────
# Guard: sections 2–3 must have run first
if (!exists("CRS_UTM") || !exists("sg_stack_utm")) {
  stop("Run this script from the top (sections 0–3 define CRS_UTM and sg_stack_utm).")
}

# Soil points file path — accepts gpkg, shp, geojson, csv, or txt.
# For CSV/TXT the file must contain lon/lat columns (e.g. LONG/LAT, lon/lat,
# longitude/latitude). Vector files are reprojected automatically.
SOIL_POINTS_FILE <- file.path(DATA_DIR, "soils_points.csv")

log_msg(sprintf("Loading soil profiles from %s...", SOIL_POINTS_FILE))

soil_pts <- read_soil_points(SOIL_POINTS_FILE, crs_out = CRS_UTM)

log_msg(sprintf("  %d points loaded (CRS: EPSG:%s)", nrow(soil_pts), CRS_UTM))

sg_extracted <- terra::extract(sg_stack_utm, vect(soil_pts), ID = FALSE)

# Prefix all SoilGrids columns to avoid name collision with measured columns
names(sg_extracted) <- paste0("sg_", names(sg_extracted))

# Extract coordinates in both UTM (from current CRS) and WGS84 (lon/lat)
coords_utm   <- st_coordinates(soil_pts)
coords_wgs84 <- st_coordinates(st_transform(soil_pts, 4326))

coords_df <- tibble(
  longitude = coords_wgs84[, "X"],
  latitude  = coords_wgs84[, "Y"],
  easting   = coords_utm[, "X"],
  northing  = coords_utm[, "Y"]
)

df_out <- bind_cols(
  st_drop_geometry(soil_pts),
  coords_df,
  sg_extracted
)

pts_file <- file.path(OUT_DIR, "soilgrids_at_points.csv")
write_csv(df_out, pts_file)
log_msg(sprintf("Point extraction (%d profiles × %d SG vars) saved → %s",
                nrow(df_out), length(soil_rasters), pts_file), "SUCCESS")

# Quick preview
cat("\n── SoilGrids 250 m values at soil profile points (first 6 rows) ─────\n")
df_out |>
  select(longitude, latitude, starts_with("sg_")) |>
  head(6) |>
  print()

# ── 5. MAP ALL VARIABLES ──────────────────────────────────────────────────────

log_msg("Plotting variable maps → figures/sg_maps_250m.png...")

n_v   <- nlyr(sg_stack_utm)
n_col <- 5
n_row <- ceiling(n_v / n_col)

png(file.path(OUT_FIG, "sg_maps_250m.png"),
    width  = n_col * 420,
    height = n_row * 400,
    res    = 120)

plot(sg_stack_utm,
     col   = viridis(100),
     main  = VAR_LABELS[names(sg_stack_utm)],
     axes  = FALSE,
     mar   = c(1, 1, 2.8, 3.5))

dev.off()
log_msg("Saved figures/sg_maps_250m.png", "SUCCESS")

# ── 6. SUMMARY ────────────────────────────────────────────────────────────────

cat("\n=== 6_soilgrids_download.R complete ===\n\n")
cat("Source  : ISRIC SoilGrids 2.0 VRT (250 m native resolution)\n")
cat("Method  : /vsicurl/ streaming — no full global file downloaded\n")
cat("Depth   :", DEPTH_LAYER, "\n")
cat("Variables downloaded:\n")
for (v in names(soil_rasters))
  cat(sprintf("  %-10s  %s\n", v, VAR_LABELS[v]))

cat("\nOutputs:\n")
cat("  Individual rasters : data/soilgrids_250m/soilgrids_<var>_15-30cm.tif\n")
cat("  Multi-band UTM stack:", stack_file, "\n")
cat("  Profile extraction :", pts_file, "\n")
cat("  Maps               : figures/sg_maps_250m.png\n")

# =============================================================================
# END OF SCRIPT
# =============================================================================
