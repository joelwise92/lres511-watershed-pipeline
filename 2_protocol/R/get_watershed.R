# Stage 1: watershed boundary from the USGS Watershed Boundary Dataset (WBD).

# Download the HUC12 boundary named in the config and save it unchanged
# to 1_input/watershed/. Returns the file path so targets can track it.
#
# If this watershed's boundary was already downloaded, that file is reused,
# as for streams: raw files are never edited, so an existing file is as valid
# as a new download, and reusing it avoids depending on the web service. Its
# original download is already in the retrieval log. To download again,
# delete the file or set refresh = TRUE.
get_watershed <- function(config, refresh = FALSE) {
  huc     <- config$study_area$huc12
  out_dir <- "1_input/watershed"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, paste0("wbd_huc12_", huc, ".gpkg"))
  
  if (file.exists(out_file) && !refresh) {
    message("Using existing watershed download: ", out_file)
    return(out_file)
  }
  
  # nhdplusTools returns nothing (with warnings) when the USGS service times
  # out, which looks the same as a HUC12 code that doesn't exist
  boundary <- tryCatch(
    suppressWarnings(nhdplusTools::get_huc(id = huc, type = "huc12")),
    error = function(e) NULL)
  if (is.null(boundary) || nrow(boundary) == 0) {
    stop("No HUC12 boundary returned for ", huc, ". If this code is correct (it is ",
         "12 digits and has worked before), the USGS Watershed Boundary Dataset ",
         "service is most likely down or timing out: wait, then run tar_make() ",
         "again. If the code is new, check it with find_huc12().")
  }
  
  sf::st_write(boundary, out_file, delete_dsn = TRUE, quiet = TRUE)
  
  log_retrieval(
    layer   = "watershed_boundary",
    source  = "USGS Watershed Boundary Dataset via nhdplusTools::get_huc()",
    url     = "https://www.usgs.gov/national-hydrography/watershed-boundary-dataset",
    version = paste0("WBD record load date ", format(max(boundary$loaddate), "%Y-%m-%d"),
                     "; nhdplusTools ", utils::packageVersion("nhdplusTools")),
    file    = out_file
  )
  out_file
}

# Helper for choosing a pilot watershed: returns the HUC12 that contains
# a point. Not part of the pipeline; run interactively.
# Example: find_huc12(lon = -111.0, lat = 45.5)
find_huc12 <- function(lon, lat) {
  pt <- sf::st_sfc(sf::st_point(c(lon, lat)), crs = 4326)
  hu <- nhdplusTools::get_huc(AOI = pt, type = "huc12")
  sf::st_drop_geometry(hu)
}