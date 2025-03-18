library(RSAGA)

env <- rsaga.env()


# Using tools SAGA (https://saga-gis.sourceforge.io/saga_tool_doc/9.5.1/ta_morphometry.html)

# list tools of morphometry 
modules_morphometry <- rsaga.get.modules(libs = "ta_morphometry", env = env)

# show detailed information of the tool
use_slope <- rsaga.get.usage(lib = "ta_morphometry", module = "Slope, Aspect, Curvature")

# Calculate slope and aspect using RSAGA
rsaga.geoprocessor(lib = "ta_morphometry", 
                  module = "Slope, Aspect, Curvature",
                  param = list(ELEVATION = "outputs/torobamba_dem_utm.tif", 
                                SLOPE = "outputs/slope_saga.tif",
                                ASPECT = "outputs/aspect_saga.tif",
                                UNIT_SLOPE = 0, # 0 = radians, 1 = degree, 2 = percent
                                UNIT_ASPECT = 0, # 0 = radians, 1 = degree
                                METHOD = 6), 
                  env = env)

# Using functions, revise: help(rsaga.slope.asp.curv)

rsaga.slope.asp.curv(in.dem = "outputs/torobamba_dem_utm.tif",
                     out.slope = "outputs/slope_copia_saga.tif",
                     out.aspect = "outputs/aspect_copia_saga.tif",
                     unit.slope = "radians",
                     unit.aspect = "radians",
                     method = "poly2evans",
                     env = env)


# Calculate Tppography Position Index (TPI) using RSAGA
use_tpi <- rsaga.get.usage(lib = "ta_morphometry", 18)

rsaga.geoprocessor(lib = "ta_morphometry", 
                  module = "Topographic Position Index (TPI)",
                  param = list(DEM = "outputs/torobamba_dem_utm.tif",  
                                TPI = "outputs/tpi_saga.tif",
                                DW_WEIGHTING = 1), 
                  env = env)


# list tools of hydrology
modules_hydrology <- rsaga.get.modules(libs = "ta_hydrology", env = env)

# Calculate SAGA Wetness Index using RSAGA
use_wetness <- rsaga.get.usage(lib = "ta_hydrology", 15)

rsaga.geoprocessor(lib = "ta_hydrology", 
                  module = "SAGA Wetness Index",
                  param = list(DEM = "outputs/torobamba_dem_utm.tif",
                                AREA = "outputs/catched_area_saga.tif",
                                TWI = "outputs/wetness_index_saga.tif"), 
                  env = env)

# Using functions, revise: help(rsaga.wetness.index)
rsaga.wetness.index("outputs/torobamba_dem_utm.tif", 
                    "outputs/wetness_index_copia_saga.tif", 
                    "outputs/catched_area_copia_saga.tif", 
                    env = env)


# Calculate LS-Factor using RSAGA
use_lsfactor <- rsaga.get.usage(lib = "ta_hydrology", 22)

rsaga.geoprocessor(lib = "ta_hydrology", 
                  module = "LS Factor",
                  param = list(SLOPE = "outputs/slope_saga.tif",
                                AREA = "outputs/catched_area_saga.tif",
                                LS = "outputs/lsfactor_saga.tif",
                              METHOD = 2), 
                  env = env)


