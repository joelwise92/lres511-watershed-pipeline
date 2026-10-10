# Stage 1: stream network from NHDPlus High Resolution (NHDPlus HR).
#
# Queries the USGS NHDPlus HR web service for network flowlines that
# intersect the watershed and saves them unchanged to 1_input/streams/.
# Flowlines that cross the boundary are returned whole; clipping to the
# watershed happens later in harmonization.

get_streams <- function(watershed_file) {
  boundary <- sf::st_read(watershed_file, quiet = TRUE)
  huc <- boundary$huc12[1]
  
  flowlines <- nhdplusTools::get_nhdphr(
    AOI  = sf::st_geometry(boundary),
    type = "networknhdflowline"
  )
  if (is.null(flowlines) || nrow(flowlines) == 0) {
    stop("No NHDPlus HR flowlines returned for HUC12 ", huc)
  }
  
  out_dir <- "1_input/streams"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0("nhdplushr_flowlines_huc12_", huc, ".gpkg"))
  sf::st_write(flowlines, out_file, delete_dsn = TRUE, quiet = TRUE)
  
  # Save the web service's description as source metadata. A failed
  # download gives a warning rather than stopping the pipeline.
  service_url <- "https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer"
  meta_dir <- "1_input/source_metadata/streams"
  dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
  tryCatch(
    utils::download.file(paste0(service_url, "?f=pjson"),
                         file.path(meta_dir, "nhdplushr_mapserver.json"),
                         mode = "wb", quiet = TRUE),
    error = function(e) warning("Could not download metadata: ", service_url)
  )
  
  log_retrieval(
    layer   = "streams",
    source  = "USGS NHDPlus HR network flowlines via nhdplusTools::get_nhdphr()",
    url     = service_url,
    version = paste0(nrow(flowlines), " flowlines; nhdplusTools ",
                     utils::packageVersion("nhdplusTools")),
    file    = out_file
  )
  out_file
}