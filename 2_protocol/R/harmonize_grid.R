# Spatial harmonization: put every layer in the same coordinate reference
# system (CRS), on the same grid, and within the same watershed extent.
#
# Settings come from the config file:
#   crs           EPSG code for all outputs
#   resolution_m  grid cell size in meters
#
# Intermediate (unclipped) rasters go to 3_incremental/reprojected/.
# Reprojected and clipped vectors go to 3_incremental/clipped/; their
# attributes are harmonized next (harmonize_attributes.R) before they are
# written to 4_product/data/. The DEM needs no attribute step, so its
# final version goes straight to 4_product/data/.

# Read the watershed boundary in the output CRS.
read_watershed <- function(watershed_file, config) {
  sf::st_transform(sf::st_read(watershed_file, quiet = TRUE), config$crs)
}

# Build the common grid ("template") that every raster is aligned to.
# The extent is the watershed's bounding box, snapped outward to whole
# multiples of the cell size. Snapping means grids for different
# watersheds line up cell-for-cell with each other.
make_template <- function(ws, config) {
  res <- config$resolution_m
  bb  <- sf::st_bbox(ws)
  terra::rast(
    xmin = floor(bb[["xmin"]] / res) * res,
    xmax = ceiling(bb[["xmax"]] / res) * res,
    ymin = floor(bb[["ymin"]] / res) * res,
    ymax = ceiling(bb[["ymax"]] / res) * res,
    resolution = res,
    crs = paste0("EPSG:", config$crs)
  )
}

# DEM: reproject onto the template with bilinear resampling (elevation is
# continuous), then mask to the watershed. Written as a cloud-optimized
# GeoTIFF with -9999 as the NoData value.
harmonize_dem <- function(dem_file, watershed_file, config) {
  ws       <- read_watershed(watershed_file, config)
  huc      <- ws$huc12[1]
  template <- make_template(ws, config)
  
  dem      <- terra::rast(dem_file)
  dem_proj <- terra::project(dem, template, method = "bilinear")
  
  inc_dir <- "3_incremental/reprojected"
  dir.create(inc_dir, recursive = TRUE, showWarnings = FALSE)
  terra::writeRaster(dem_proj, file.path(inc_dir, paste0("dem_", huc, ".tif")),
                     overwrite = TRUE)
  
  dem_final <- terra::mask(dem_proj, terra::vect(ws))
  names(dem_final) <- "elevation_m"
  
  out_dir <- "4_product/data"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0("dem_", huc, "_", config$resolution_m, "m.tif"))
  terra::writeRaster(dem_final, out_file, filetype = "COG", datatype = "FLT4S",
                     NAflag = -9999, overwrite = TRUE)
  out_file
}

# Watershed boundary: reproject to the output CRS.
harmonize_watershed <- function(watershed_file, config) {
  ws  <- read_watershed(watershed_file, config)
  huc <- ws$huc12[1]
  
  out_dir <- "3_incremental/clipped"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0("watershed_", huc, ".gpkg"))
  sf::st_write(ws, out_file, delete_dsn = TRUE, quiet = TRUE)
  out_file
}

# Streams: reproject to the output CRS and clip to the watershed.
harmonize_streams <- function(streams_file, watershed_file, config) {
  ws      <- read_watershed(watershed_file, config)
  huc     <- ws$huc12[1]
  streams <- sf::st_transform(sf::st_read(streams_file, quiet = TRUE), config$crs)
  
  # Clip with the boundary geometry only, so no watershed attributes are
  # added to the stream table
  streams_clip <- suppressWarnings(sf::st_intersection(streams, sf::st_geometry(ws)))
  
  out_dir <- "3_incremental/clipped"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0("streams_", huc, ".gpkg"))
  sf::st_write(streams_clip, out_file, delete_dsn = TRUE, quiet = TRUE)
  out_file
}