# Stage 2: harmonize NOAA Atlas 14 grids onto the common grid.
#
# For each downloaded zip:
#   1. read the ASCII grid directly from the zip (the zip stays unchanged)
#   2. assign NAD83 geographic coordinates if the grid has no CRS
#   3. crop to the watershed plus a 2 km buffer
#   4. convert depth to intensity using the crosswalk's multiply_by value
#      (thousandths of an inch over the duration -> mm/hr)
#   5. resample (bilinear) to the common grid and mask to the watershed
#
# Layer names come from the file names, e.g. inw2yr30ma.zip ->
# precip_2yr_30m, and must match a crosswalk row.

harmonize_precip <- function(precip_files, watershed_file, crosswalk_file, config) {
  ws       <- read_watershed(watershed_file, config)
  huc      <- ws$huc12[1]
  template <- make_template(ws, config)
  aoi      <- terra::vect(sf::st_buffer(ws, 2000))
  cw       <- utils::read.csv(crosswalk_file, colClasses = "character", na.strings = "")
  
  out_dir <- "4_product/data"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  files <- vapply(precip_files, function(f) {
    layer <- sub("^[a-z]+([0-9]+yr)([0-9]+[mhd])a\\.zip$", "precip_\\1_\\2", basename(f))
    row   <- cw[cw$layer == layer & toupper(cw$keep) == "TRUE", ]
    if (nrow(row) != 1) stop("Expected one crosswalk row for ", layer, ", found ", nrow(row))
    
    asc <- grep("\\.asc$", utils::unzip(f, list = TRUE)$Name, value = TRUE)[1]
    r   <- terra::rast(paste0("/vsizip/", normalizePath(f, winslash = "/"), "/", asc))
    if (terra::crs(r) == "") terra::crs(r) <- "EPSG:4269"
    
    r <- terra::crop(r, terra::project(aoi, terra::crs(r)))
    r <- r * as.numeric(row$multiply_by)
    r <- terra::project(r, template, method = "bilinear")
    r <- terra::mask(r, terra::vect(ws))
    names(r) <- layer
    
    out <- file.path(out_dir, paste0(layer, "_", huc, "_", config$resolution_m, "m.tif"))
    terra::writeRaster(r, out, filetype = "COG", datatype = "FLT4S",
                       NAflag = -9999, overwrite = TRUE)
    out
  }, character(1))
  unname(files)
}