# Stage 3 (test): forest structure from LANDFIRE via the LANDFIRE Product
# Service (LFPS), using rlandfire.
#
# Requests the products listed in the config (e.g. canopy cover and canopy
# height) for the watershed plus a 1 km buffer, in the output CRS, and saves
# the returned zip unchanged to 1_input/forest/. A record of the request is
# saved as source metadata.
#
# An existing download for this watershed and product set is reused. To
# force a new request, delete the file or set refresh = TRUE.
#
# Config settings (study_area.yml):
#   forest:
#     email: "you@example.edu"           # required by LANDFIRE for each request
#     products: ["LF2024_CC", "LF2024_CH"]

get_forest <- function(watershed_file, config, refresh = FALSE) {
  ws       <- sf::st_read(watershed_file, quiet = TRUE)
  huc      <- ws$huc12[1]
  products <- unlist(config$forest$products)
  
  out_dir  <- "1_input/forest"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0("landfire_", paste(products, collapse = "_"),
                                        "_huc12_", huc, ".zip"))
  
  if (file.exists(out_file) && !refresh) {
    message("Using existing LANDFIRE download: ", out_file)
    return(out_file)
  }
  
  aoi  <- rlandfire::getAOI(sf::st_transform(ws, config$crs), extend = 1000)
  resp <- rlandfire::landfireAPIv2(products   = products,
                                   aoi        = aoi,
                                   email      = config$forest$email,
                                   projection = config$crs,
                                   path       = tempfile(fileext = ".zip"))
  if (is.null(resp$path) || !file.exists(resp$path)) {
    stop("The LANDFIRE request for HUC12 ", huc, " did not return a file. ",
         "The LANDFIRE Product Service may be busy or down; wait and run tar_make() again.")
  }
  file.copy(resp$path, out_file, overwrite = TRUE)
  
  # Record of the request (LANDFIRE's own product metadata is online)
  meta_dir <- "1_input/source_metadata/forest"
  dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c(
    paste("Products:", paste(products, collapse = ", ")),
    paste("AOI (lon/lat):", paste(aoi, collapse = ", ")),
    paste("Projection requested: EPSG", config$crs),
    paste("Requested:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste("Files in zip:", paste(utils::unzip(out_file, list = TRUE)$Name, collapse = ", "))
  ), file.path(meta_dir, paste0("landfire_request_", huc, ".txt")))
  
  log_retrieval(
    layer   = "forest",
    source  = "LANDFIRE Product Service v2 via rlandfire::landfireAPIv2()",
    url     = "https://lfps.usgs.gov",
    version = paste0(paste(products, collapse = ", "), "; rlandfire ",
                     utils::packageVersion("rlandfire")),
    file    = out_file
  )
  out_file
}