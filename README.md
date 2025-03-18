# Soil, Topography and Climate Analysis Tools

This repository contains R scripts for analyzing and processing soil, topography, and climate data using various R packages including Terra, RSAGA, WhiteBox, and others.

## Repository Overview

This toolset allows for:
- Digital Elevation Model (DEM) acquisition and processing
- Terrain analysis (slope, aspect, TPI, etc.)
- Hydrological modeling and analysis
- Climate data acquisition and processing
- Soil data acquisition

## Required Packages

The following R packages are required:

```r
# Spatial data handling
library(terra)     # Modern spatial data processing
library(sf)        # Simple features for R

# Elevation data
library(elevatr)   # For downloading elevation data

# Terrain analysis
library(whitebox)  # WhiteBox tools interface
library(RSAGA)     # SAGA GIS interface

# Climate and soil data
library(geodata)   # For downloading climate and soil data

# Visualization
library(ggplot2)   # Data visualization
library(patchwork) # Combine plots


# Creating a README for your repository

I will create a comprehensive README.md file that explains the purpose, structure, and usage of the tools implemented for soil, topography, and climate analysis.



```markdown
# Soil, Topography and Climate Analysis Tools

This repository contains R scripts for analyzing and processing soil, topography, and climate data using various R packages including Terra, RSAGA, WhiteBox, and others.

## Repository Overview

This toolset allows for:
- Digital Elevation Model (DEM) acquisition and processing
- Terrain analysis (slope, aspect, TPI, etc.)
- Hydrological modeling and analysis
- Climate data acquisition and processing
- Soil data acquisition

## Required Packages

The following R packages are required:

```r
# Spatial data handling
library(terra)     # Modern spatial data processing
library(sf)        # Simple features for R

# Elevation data
library(elevatr)   # For downloading elevation data

# Terrain analysis
library(whitebox)  # WhiteBox tools interface
library(RSAGA)     # SAGA GIS interface

# Climate and soil data
library(geodata)   # For downloading climate and soil data

# Visualization
library(ggplot2)   # Data visualization
library(patchwork) # Combine plots
```

## Script Descriptions

### 1. Terra Package (`1_use_terra.R`)

Uses the `terra` package for:
- Extracting point elevations
- Downloading DEMs from different sources (AWS, ALOS, SRTM)
- Basic terrain analysis (slope, aspect, TPI, TRI)
- Hydrological analysis (flow direction, flow accumulation, watershed delineation)
- Visualization of results

### 2. RSAGA Package (`2_use_rsaga.R`) 

Uses SAGA GIS via the `RSAGA` package for:
- Advanced terrain analysis (slope, aspect, curvature)
- Topographic Position Index (TPI)
- SAGA Wetness Index
- LS-Factor calculation for erosion modeling

### 3. WhiteBox Tools (`3_use_whitebox.R`)

Uses WhiteBox tools via the `whitebox` package for:
- Hillshade generation
- Slope calculation
- Hydrological analysis (depression filling, flow accumulation)
- Topographic Wetness Index (TWI) calculation

### 4. Climate and Soil Data (`4_climate_soil.R`)

Uses the `geodata` package for:
- Downloading WorldClim climate data
- Processing temperature and precipitation data
- Downloading and processing soil data from SoilGrids

## Data Structure

- `/data/`: Contains input data files
  - Watershed boundary shapefile (`borde_torobamba_geo.shp`)
  - Sample soil points (`soils_points.csv`)
  
- `/outputs/`: Directory for generated outputs
  - Processed DEM files
  - Terrain analysis results
  - Climate data
  
- `/log/`: Contains log information

## Example Usage

1. Extract point elevations and download DEM:
```r
# Run Terra script for DEM acquisition and basic processing
source("1_use_terra.R")
```

2. Perform terrain analysis with RSAGA:
```r
# Run RSAGA script for advanced terrain analysis
source("2_use_rsaga.R")
```

3. Use WhiteBox tools for hydrological analysis:
```r
# First time use requires installation
# whitebox::install_whitebox()
source("3_use_whitebox.R")
```

4. Download and process climate and soil data:
```r
# Set geodata default path
options(geodata_default_path = "./geodata")
source("4_climate_soil.R")
```

## Notes

- For WhiteBox Tools, initialization is required: `whitebox::wbt_init()`
- For OpenTopography API, a key needs to be set: `elevatr::set_opentopo_key()`
- For SAGA tools, environment setup may be required
- When using Terra with custom projections: `terra:::.set_proj_search_paths("C:/OSGeo4W/share/proj")`

## Example Outputs

The scripts generate various outputs including:
- DEM files in different formats
- Terrain derivatives (slope, aspect, etc.)
- Hydrological indices (TWI, flow accumulation)
- Climate and soil rasters

All outputs are saved in the `/outputs/` directory with visualization plots.