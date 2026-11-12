# Stage 1: stream network from NHDPlus High Resolution (NHDPlus HR).
#
# Queries the USGS NHDPlus HR web service for network flowlines in the
# watershed and saves them unchanged to 1_input/streams/. Flowlines that
# cross the boundary are kept whole; clipping happens in harmonization.
#
# If this watershed's streams were already downloaded, that file is reused.
#
# The service can time out on large requests or when it is unstable, so
# the watershed's bounding box is split into tiles (2 x 2 by default).
# Each tile is queried separately and retried after a pause if it fails.
# The tiles are then combined, duplicates (flowlines crossing tile edges)
# removed, and only flowlines touching the watershed kept, which gives
# the same result as one whole-watershed query.

get_streams <- function(watershed_file, tiles = 2, attempts = 4, wait_s = 15,
                        refresh = FALSE) {
  boundary <- sf::st_read(watershed_file, quiet = TRUE)
  huc <- boundary$huc12[1]
  service_url <- "https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer"
  out_dir  <- "1_input/streams"
  out_file <- file.path(out_dir, paste0("nhdplushr_flowlines_huc12_", huc, ".gpkg"))
  
  # Reuse an earlier download of this watershed's streams. Raw files are never
  # edited, so an existing file is as valid as a new download, and reusing it
  # avoids depending on the web service. Its original download is already in
  # the retrieval log. To force a fresh download, delete the file or set
  # refresh = TRUE.
  if (file.exists(out_file) && !refresh) {
    message("Using existing stream download: ", out_file)
    return(out_file)
  }
  
  # Is the service up at all?
  service_ok <- tryCatch({
    readLines(paste0(service_url, "?f=json"), n = 1, warn = FALSE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!service_ok) {
    stop("The USGS NHDPlus HR web service is not responding (", service_url, "). ",
         "This is a service outage, not a problem with HUC12 ", huc, ". ",
         "Wait, then run tar_make() again; finished steps will be skipped.")
  }
  
  # Tiles covering the watershed (only those that touch it)
  cells <- sf::st_make_grid(boundary, n = c(tiles, tiles))
  cells <- cells[lengths(sf::st_intersects(cells, boundary)) > 0]
  
  # Query each tile, retrying with a growing pause
  parts <- lapply(seq_along(cells), function(i) {
    for (a in seq_len(attempts)) {
      # A failed request can either return nothing or raise an error inside
      # nhdplusTools (e.g. "subscript out of bounds"); treat both as a failed try
      p <- tryCatch(
        suppressWarnings(
          nhdplusTools::get_nhdphr(AOI = cells[i], type = "networknhdflowline")),
        error = function(e) NULL)
      if (!is.null(p) && nrow(p) > 0) return(p)
      if (a < attempts) Sys.sleep(wait_s * a)
    }
    NULL
  })
  
  failed <- which(vapply(parts, is.null, logical(1)))
  if (length(failed) > 0) {
    stop("NHDPlus HR did not return flowlines for ", length(failed), " of ",
         length(cells), " tiles of HUC12 ", huc, " after ", attempts, " attempts each. ",
         "The service is most likely timing out (it reports timeouts the same way ",
         "as an area with no streams). Wait, then run tar_make() again.")
  }
  
  # Combine, remove duplicates, keep flowlines that touch the watershed
  flowlines <- do.call(rbind, parts)
  flowlines <- flowlines[!duplicated(flowlines$nhdplusid), ]
  flowlines <- sf::st_filter(flowlines, sf::st_transform(boundary, sf::st_crs(flowlines)))
  
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  sf::st_write(flowlines, out_file, delete_dsn = TRUE, quiet = TRUE)
  
  # Save the web service's description as source metadata. A failed
  # download gives a warning rather than stopping the pipeline.
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
    source  = "USGS NHDPlus HR network flowlines via nhdplusTools::get_nhdphr(), queried in tiles",
    url     = service_url,
    version = paste0(nrow(flowlines), " flowlines from ", length(cells), " tiles; nhdplusTools ",
                     utils::packageVersion("nhdplusTools")),
    file    = out_file
  )
  out_file
}