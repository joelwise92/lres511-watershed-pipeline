# Stage 3: roads from the USFS National Forest System Roads layer.
#
# Queries the Forest Service Enterprise Data Warehouse (EDW) map service
# EDW_RoadBasic_01, layer 0 ("National Forest System Roads"), for road
# segments touching the watershed and saves them unchanged to 1_input/roads/
# in the service's native coordinate system (NAD83 geographic, EPSG:4269).
# Segments that cross the boundary are kept whole; clipping happens in
# harmonization.
#
# Only National Forest System roads are included. County, state, and private
# roads are not, so a watershed outside national forest land gets an empty
# (but valid) roads layer.
#
# EDW road data are updated daily from the national forests' databases, so
# the retrieval date is the effective version. If this watershed's roads were
# already downloaded, that file is reused (set refresh = TRUE, or delete the
# file, to download again).

get_roads <- function(watershed_file, attempts = 3, wait_s = 15, page_size = 2000,
                      refresh = FALSE) {
  boundary <- sf::st_read(watershed_file, quiet = TRUE)
  huc <- boundary$huc12[1]
  layer_url <- "https://apps.fs.usda.gov/arcx/rest/services/EDW/EDW_RoadBasic_01/MapServer/0"
  out_dir  <- "1_input/roads"
  out_file <- file.path(out_dir, paste0("usfs_nfs_roads_huc12_", huc, ".gpkg"))
  
  if (file.exists(out_file) && !refresh) {
    message("Using existing road download: ", out_file)
    return(out_file)
  }
  
  # Is the service up at all?
  service_ok <- tryCatch({
    readLines(paste0(layer_url, "?f=json"), n = 1, warn = FALSE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE)
  if (!service_ok) {
    stop("The USFS road map service is not responding (", layer_url, "). ",
         "This is a service outage, not a problem with HUC12 ", huc, ". ",
         "Wait, then run tar_make() again; finished steps will be skipped.")
  }
  
  # Fields requested: every attribute except internal IDs and the service's
  # own geometry-length field. Numeric fields are listed separately so an
  # empty result still has the right column types.
  num_fields <- c("bmp", "emp", "seg_length", "gis_miles")
  chr_fields <- c("rte_cn", "id", "name", "symbol_code", "symbol_name", "jurisdiction",
                  "system", "route_status", "oper_maint_level", "objective_maint_level",
                  "functional_class", "surface_type", "lanes", "primary_maintainer",
                  "county", "congressional_district", "admin_org", "service_life",
                  "level_of_service", "pfsr_classification", "managing_org", "loc_error",
                  "openforuseto")
  fields <- c(chr_fields, num_fields)
  
  # Query by the watershed's bounding box; segments outside the watershed
  # itself are dropped below
  bb <- sf::st_bbox(sf::st_transform(boundary, 4269))
  
  # One page of results (the service returns at most 2,000 features per
  # request). Returns an sf object, or NULL when the page is empty.
  query_page <- function(offset) {
    params <- c(
      where             = "1=1",
      geometry          = paste(bb[["xmin"]], bb[["ymin"]], bb[["xmax"]], bb[["ymax"]],
                                sep = ","),
      geometryType      = "esriGeometryEnvelope",
      inSR              = "4269",
      spatialRel        = "esriSpatialRelIntersects",
      outFields         = paste(fields, collapse = ","),
      outSR             = "4269",
      orderByFields     = "objectid",
      resultOffset      = as.character(offset),
      resultRecordCount = as.character(page_size),
      f                 = "geojson"
    )
    url <- paste0(layer_url, "/query?",
                  paste0(names(params), "=",
                         vapply(params, utils::URLencode, character(1), reserved = TRUE),
                         collapse = "&"))
    tmp <- tempfile(fileext = ".geojson")
    for (a in seq_len(attempts)) {
      ok <- tryCatch({
        utils::download.file(url, tmp, mode = "wb", quiet = TRUE)
        # The service reports problems as JSON with an "error" member
        !grepl('^\\s*\\{\\s*"error"', paste(readLines(tmp, n = 5, warn = FALSE),
                                            collapse = ""))
      }, error = function(e) FALSE, warning = function(w) FALSE)
      if (ok) break
      if (a < attempts) Sys.sleep(wait_s * a)
    }
    if (!ok) {
      stop("The USFS road service did not return roads for HUC12 ", huc,
           " after ", attempts, " tries. This is most likely a service problem; ",
           "wait, then run tar_make() again.")
    }
    txt <- paste(readLines(tmp, warn = FALSE), collapse = "")
    if (grepl('"features"\\s*:\\s*\\[\\s*\\]', txt)) return(NULL)
    sf::st_read(tmp, quiet = TRUE)
  }
  
  parts  <- list()
  offset <- 0
  repeat {
    p <- query_page(offset)
    if (is.null(p)) break
    parts[[length(parts) + 1]] <- p
    if (nrow(p) < page_size) break
    offset <- offset + page_size
  }
  
  if (length(parts) == 0) {
    # No National Forest System roads here: write an empty layer with the
    # same columns, so later steps work the same way
    cols  <- lapply(fields, function(f) if (f %in% num_fields) numeric(0) else character(0))
    names(cols) <- fields
    roads <- sf::st_sf(as.data.frame(cols, stringsAsFactors = FALSE),
                       geometry = sf::st_sfc(crs = 4269))
  } else {
    roads <- do.call(rbind, parts)
    # GeoJSON is always read as WGS84, but the coordinates were requested in
    # NAD83 (outSR = 4269), so relabel them rather than transform them
    roads <- suppressWarnings(sf::st_set_crs(roads, 4269))
    # Keep segments that touch the watershed itself, not just its bounding box
    ws4269 <- sf::st_transform(sf::st_geometry(boundary), 4269)
    roads  <- roads[lengths(sf::st_intersects(roads, ws4269)) > 0, ]
  }
  
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  sf::st_write(roads, out_file, delete_dsn = TRUE, quiet = TRUE)
  
  # Save the provider's metadata: the layer description and metadata record
  # from the service, and the national FGDC metadata record it links to. A failed metadata download
  # gives a warning rather than stopping the pipeline.
  meta_dir <- "1_input/source_metadata/roads"
  dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
  meta <- c(
    "usfs_roads_layer0.json"         = paste0(layer_url, "?f=pjson"),
    "usfs_roads_layer0_metadata.xml" = paste0(layer_url, "/metadata"),
    "S_USA.RoadCore_FS.xml"          = "https://data.fs.usda.gov/geodata/edw/edw_resources/meta/S_USA.RoadCore_FS.xml"
  )
  for (f in names(meta)) {
    tryCatch(
      utils::download.file(meta[[f]], file.path(meta_dir, f), mode = "wb", quiet = TRUE),
      error = function(e) warning("Could not download road metadata: ", meta[[f]])
    )
  }
  
  log_retrieval(
    layer   = "roads",
    source  = "USFS National Forest System Roads (EDW_RoadBasic_01 map service, layer 0)",
    url     = layer_url,
    version = paste0("EDW road data, updated daily from national forest databases; ",
                     nrow(roads), " segments touching the watershed"),
    file    = out_file
  )
  out_file
}