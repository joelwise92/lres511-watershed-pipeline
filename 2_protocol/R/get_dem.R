# Stage 1: elevation from the USGS 3D Elevation Program (3DEP),
# 1/3 arc-second (~10 m) seamless DEM.
#
# 3DEP serves this DEM as 1 x 1 degree cloud-optimized GeoTIFF tiles named
# by their northwest corner (e.g., n47w111 covers 46-47 N, 111-110 W).
# This function finds the tiles that cover the watershed plus a buffer,
# reads only that area directly from the USGS server, and saves it to
# 1_input/dem/ with elevation values unchanged (no reprojection or
# resampling; that happens later in harmonization).

get_dem <- function(watershed_file, buffer_m = 1000) {
  boundary <- sf::st_read(watershed_file, quiet = TRUE)
  huc <- boundary$huc12[1]
  
  # Buffer the watershed so later terrain calculations have data past the edge.
  # Buffering is done in meters (EPSG:5070), then converted back to lat/long.
  aoi <- sf::st_buffer(sf::st_transform(boundary, 5070), buffer_m)
  bb  <- sf::st_bbox(sf::st_transform(aoi, 4269))
  
  # Work out which 1-degree tiles the buffered area touches
  lats <- seq(ceiling(bb[["ymin"]]), ceiling(bb[["ymax"]]))
  lons <- seq(ceiling(-bb[["xmax"]]), ceiling(-bb[["xmin"]]))
  tiles <- expand.grid(lat = lats, lon = lons)
  tile_ids <- sprintf("n%02dw%03d", tiles$lat, tiles$lon)
  
  base <- "https://prd-tnm.s3.amazonaws.com/StagedProducts/Elevation/13/TIFF/current"
  urls <- sprintf("%s/%s/USGS_13_%s.tif", base, tile_ids, tile_ids)
  
  # Read only the needed area of each tile straight from the server
  pieces <- lapply(urls, function(u) {
    r <- terra::rast(paste0("/vsicurl/", u))
    terra::crop(r, terra::project(terra::vect(aoi), terra::crs(r)))
  })
  dem <- if (length(pieces) == 1) pieces[[1]] else terra::merge(terra::sprc(pieces))
  names(dem) <- "elevation_m"
  
  out_dir <- "1_input/dem"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0("usgs_3dep_13_huc12_", huc, ".tif"))
  terra::writeRaster(dem, out_file, overwrite = TRUE)
  
  # Save the provider's metadata for each tile. A failed metadata download
  # gives a warning rather than stopping the pipeline.
  meta_dir <- "1_input/source_metadata/dem"
  dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_along(tile_ids)) {
    xml_url  <- sub("\\.tif$", ".xml", urls[i])
    xml_file <- file.path(meta_dir, paste0("USGS_13_", tile_ids[i], ".xml"))
    tryCatch(
      utils::download.file(xml_url, xml_file, mode = "wb", quiet = TRUE),
      error = function(e) warning("Could not download metadata: ", xml_url)
    )
  }
  
  log_retrieval(
    layer   = "dem",
    source  = "USGS 3DEP 1/3 arc-second seamless DEM (current), read via GDAL /vsicurl/",
    url     = paste(urls, collapse = "; "),
    version = paste0("3DEP current tiles: ", paste(tile_ids, collapse = ", "),
                     "; cropped to watershed + ", buffer_m, " m buffer"),
    file    = out_file
  )
  out_file
}