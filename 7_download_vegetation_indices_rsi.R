# =============================================================================
# Pipeline: Download Landsat imagery → compute vegetation indices →
#           extract values at soil sampling points → export plots
#
# Packages used:
#   rsi   – downloads satellite imagery from STAC APIs and computes spectral
#           indices from the Awesome Spectral Indices (ASI) database
#   sf    – reads/writes vector data (GeoPackage, shapefile) and handles CRS
#   terra – reads/writes raster data, performs crop/mask, extract operations
# =============================================================================
library(rsi)
library(sf)
library(terra)

# ── 1. Study area ─────────────────────────────────────────────────────────────
# Read the polygon that defines the study boundary.
# The file is a GeoPackage (.gpkg), a single-file OGC vector format.
study_area <- st_read('data/borde_poly.gpkg')
print(study_area)
cat("\nCRS:", as.character(st_crs(study_area)), "\n")

# Reproject to UTM Zone 18S (EPSG:32718) so that spatial distances are in
# metres and Landsat pixels snap to 30 m × 30 m correctly.
# Geographic CRS (degrees) would distort pixel sizes near the equator.
study_utm  <- st_transform(study_area, crs = 32718)

# rsi's download functions accept any sf/sfc/bbox object as the area of
# interest (aoi).  We use the bounding box of the reprojected polygon so the
# downloaded tile fully covers the study area.
aoi        <- st_as_sfc(st_bbox(study_utm))

# Keep a terra SpatVector of the polygon for crop/mask later.
study_vect <- terra::vect(study_utm)

cat("AOI CRS (for download):", as.character(st_crs(aoi)$input), "\n")
cat("AOI extent:\n"); print(st_bbox(aoi))

# ── 2. Download Landsat imagery (vegetation growing season) ───────────────────
# get_landsat_imagery() queries a STAC API for Landsat 8/9 Collection 2
# Level-2 scenes that intersect the aoi within the date window.
# It automatically:
#   • applies cloud and cloud-shadow masks (QA_PIXEL band)
#   • rescales digital numbers to surface-reflectance values (0–1 range)
#   • composites overlapping scenes (median by default)
# The growing-season window (May–Aug) maximises green-vegetation signal and
# minimises cloud cover typical of the wet season.
cat("\nDownloading Landsat imagery...\n")
get_landsat_imagery(
  aoi,
  start_date      = "2025-05-01",
  end_date        = "2025-08-31",
  output_filename = "data/landsat_imagery.tif"
)

# Load the downloaded raster into R.
imagery_raw <- terra::rast("data/landsat_imagery.tif")

# Crop to the bounding box of the polygon first (fast rectangular clip),
# then mask to the exact polygon boundary (sets outside pixels to NA).
# This removes Landsat pixels that fall outside the study area so that
# subsequent index calculations and extractions are limited to the ROI.
imagery <- terra::mask(terra::crop(imagery_raw, study_vect), study_vect)
terra::writeRaster(imagery, "data/landsat_imagery_masked.tif", overwrite = TRUE)

cat("Bands available:", paste(names(imagery), collapse = ", "), "\n")
cat("Imagery dimensions:", paste(dim(imagery)[1:2], collapse = " x "), "pixels\n")

# ── 3. Compute vegetation indices ─────────────────────────────────────────────
# Spectral indices are band-math formulas that isolate specific biophysical
# or land-surface properties.  All indices below can be derived from the
# six reflectance bands available on Landsat OLI:
#   B (Blue ~485 nm), G (Green ~560 nm), R (Red ~660 nm),
#   N (NIR ~865 nm), S1 (SWIR-1 ~1610 nm), S2 (SWIR-2 ~2200 nm)
cat("\nComputing vegetation indices...\n")

# The 10 indices are chosen for their wide adoption in precision agriculture
# and soil-vegetation studies:
#   NDVI  – (N-R)/(N+R)    General greenness; most cited VI worldwide
#   MSAVI – Modified SAVI  Reduces soil-brightness effects better than SAVI
#   GNDVI – (N-G)/(N+G)    More sensitive to chlorophyll than NDVI
#   DVI   – N-R             Linear greenness; sensitive at high biomass
#   MBI   – Modified Brightness Index  Highlights bare/bright soils
#   VARI  – (G-R)/(G+R-B)  Atmospheric-resistant VI using visible bands only
#   GLI   – Green Leaf Index  Combines G, R, B; strong in dense canopies
#   BI    – Bare Soil Index  Isolates unvegetated mineral surfaces
#   NBR   – (N-S2)/(N+S2)  Sensitive to fire burn severity and dry biomass
#   NDMI  – (N-S1)/(N+S1)  Tracks canopy water content / moisture stress
popular_veg <- c(
  "NDVI",
  "MSAVI",
  "GNDVI",
  "DVI",
  "MBI",
  "VARI",
  "GLI",
  "BI",
  "NBR",
  "NDMI"
)

# filter_bands() queries the Awesome Spectral Indices (ASI) database and
# returns only those index definitions whose formulas require a subset of the
# bands we actually have.  This prevents errors from missing bands (e.g.,
# red-edge bands available on Sentinel-2 but not on Landsat OLI).
landsat_bands <- c("R", "N", "G", "B", "S1", "S2")
idx_table     <- filter_bands(bands = landsat_bands)

# Keep only the 10 target indices from the filtered table.
veg_idx_table <- idx_table[idx_table$short_name %in% popular_veg, ]

cat("Selected", nrow(veg_idx_table), "of", length(popular_veg), "requested indices\n")
cat("Index names:", paste(sort(veg_idx_table$short_name), collapse = ", "), "\n\n")

# calculate_indices() evaluates each index formula in the ASI table against
# the named bands of `imagery` and writes a multi-layer raster where every
# layer corresponds to one index.
calculate_indices(imagery, veg_idx_table,
                  output_filename = "data/vegetation_indices.tif")

veg_raw <- terra::rast("data/vegetation_indices.tif")

# Apply the same crop/mask as the imagery to keep index and imagery extents
# identical and to ensure pixels outside the study area are NA.
veg_indices <- terra::mask(terra::crop(veg_raw, study_vect), study_vect)
terra::writeRaster(veg_indices, "data/vegetation_indices_masked.tif", overwrite = TRUE)

cat("Vegetation indices saved to data/vegetation_indices_masked.tif\n")
cat("Total computed:", terra::nlyr(veg_indices), "indices\n")

# ── 4. Extract indices at soil sampling points ────────────────────────────────
# Pair each soil sample with the index values of the pixel it falls in.
# This creates a tabular dataset suitable for correlation analysis,
# regression modelling, or machine learning (soil property ~ spectral index).
cat("\nReading soil sampling points...\n")
soils    <- read.csv('data/soils_points.csv')

# Convert the CSV to an sf object using the longitude/latitude columns.
# CRS 4326 = WGS-84 geographic (the standard for GPS coordinates).
soils_sf <- st_as_sf(soils, coords = c("longitude", "latitude"), crs = 4326)

# terra::extract() requires the points and raster to share the same CRS.
# Reproject from WGS-84 to the raster's CRS (UTM 18S).
soils_sf_proj <- st_transform(soils_sf, crs = terra::crs(veg_indices))

cat("Extracting index values at", nrow(soils), "soil sample locations...\n")

# ID = FALSE omits the automatically generated "ID" column so that cbind()
# aligns cleanly with the original soils data frame.
extracted     <- terra::extract(veg_indices, terra::vect(soils_sf_proj), ID = FALSE)
soils_indices <- cbind(soils, extracted)

write.csv(soils_indices, "data/soils_with_indices.csv", row.names = FALSE)
cat("Results saved to data/soils_with_indices.csv\n")

cat("\nSummary of extracted vegetation indices:\n")
print(summary(extracted))

# Diagnose how many sample points fell outside valid raster pixels (NA).
# High NA fractions may indicate misaligned CRS, points outside the masked
# area, or cloud-masked pixels at those locations.
na_frac <- colMeans(is.na(extracted))
cat("\nProportion of NAs per index (first 10):\n")
print(round(head(sort(na_frac), 10), 3))

# Retain only index columns that have at least one valid (non-NA) value
# so that downstream plots and analyses are not broken by all-NA columns.
valid_cols  <- names(extracted)[na_frac < 1]
extracted_v <- extracted[, valid_cols, drop = FALSE]
cat("\nIndices with valid extracted values:", length(valid_cols), "/", ncol(extracted), "\n")

# ── 5. Plots ──────────────────────────────────────────────────────────────────
# Three complementary visualisations:
#   5a. Spatial maps of key indices  → spatial patterns across the study area
#   5b. NDVI map overlaid with soil sample locations → extraction QA check
#   5c. Boxplot of extracted values  → distribution at sample points
cat("\nGenerating plots...\n")
dir.create("data/plots", showWarnings = FALSE)

# Diverging palette: red (low/negative) → yellow (zero) → green (high).
# Suitable for most vegetation indices whose expected range is roughly -1 to 1.
veg_pal <- colorRampPalette(c("#d73027", "#fee090", "#1a9850"))(100)

# 5a. Spatial maps of key indices ─────────────────────────────────────────────
# ARVI is included in the target list in case it was computed; it relies on
# blue band for atmospheric correction and may not always be available.
key_idx       <- c("NDVI", "GNDVI", "ARVI", "MSAVI", "NBR", "BI", "VARI", "GLI")
available_key <- key_idx[key_idx %in% names(veg_indices)]  # guard against missing layers

if (length(available_key) > 0) {
  nc <- min(4L, length(available_key))           # up to 4 columns per row
  nr <- ceiling(length(available_key) / nc)      # rows needed
  png("data/plots/key_vegetation_indices.png",
      width = 500 * nc, height = 450 * nr, res = 120)
  par(mfrow = c(nr, nc), mar = c(3, 3, 3, 4))
  for (idx in available_key) {
    terra::plot(veg_indices[[idx]], main = idx, col = veg_pal,
                plg = list(cex = 0.8))
  }
  dev.off()
  cat("Key indices map saved to data/plots/key_vegetation_indices.png\n")
}

# 5b. NDVI map with soil sampling points overlaid ─────────────────────────────
# Overlaying sample points on the NDVI map lets you visually check that
# points land inside the valid (non-NA) raster area and helps interpret
# whether samples were collected across a gradient of vegetation density.
if ("NDVI" %in% names(veg_indices)) {
  png("data/plots/ndvi_soil_points.png", width = 900, height = 800, res = 120)
  terra::plot(veg_indices[["NDVI"]],
              main = "NDVI with Soil Sampling Points",
              col  = veg_pal)
  terra::points(terra::vect(soils_sf_proj),
                col = "blue", pch = 16, cex = 0.9)
  legend("bottomright", legend = "Soil samples",
         pch = 16, col = "blue", bg = "white", cex = 0.9)
  dev.off()
  cat("NDVI + soil points saved to data/plots/ndvi_soil_points.png\n")
}

# 5c. Boxplot of index values at soil sampling points ─────────────────────────
# Side-by-side boxplots show the range and spread of each index across all
# sampling locations.  Indices with narrow ranges or many outliers may carry
# less discriminatory power for soil-property modelling.
# `outline = FALSE` suppresses individual outlier dots to keep the plot clean.
n_idx <- ncol(extracted_v)
if (n_idx > 0) {
  png("data/plots/indices_boxplot.png",
      width = max(900, 35 * n_idx), height = 600, res = 120)
  par(mar = c(9, 4, 4, 2))          # large bottom margin for rotated labels
  boxplot(extracted_v,
          las     = 2,              # rotate x-axis labels 90°
          main    = "Vegetation Indices at Soil Sampling Points",
          ylab    = "Index value",
          col     = "lightgreen",
          outline = FALSE)
  abline(h = 0, lty = 2, col = "grey50")   # reference line at zero
  dev.off()
  cat("Boxplot saved to data/plots/indices_boxplot.png\n")
}

cat("\nDone! All outputs are in data/ and data/plots/\n")
