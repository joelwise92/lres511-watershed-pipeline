# Stage 2: soils from SSURGO via the NRCS Soil Data Access (SDA) service.
#
# Downloads, unchanged:
#   - soil map unit polygons intersecting the watershed (whole polygons)
#   - component and horizon records for those map units, including
#     K-factors (kwfact, kffact)
# Also saves the survey area name and version date as source metadata.
# Returns two file paths: the polygons, then the horizon table.

# Stop with a clear message when Soil Data Access returns something other
# than a table (an error object or NA), which happens during service
# outages. Without this, the failure shows up later as a cryptic error.
check_sda <- function(x, what, huc) {
  if (!is.data.frame(x)) {
    msg <- if (inherits(x, "error")) conditionMessage(x) else
      paste("returned", paste(class(x), collapse = "/"))
    stop("NRCS Soil Data Access did not return ", what, " for HUC12 ", huc, " (", msg,
         "). This is most likely a service outage, not a problem with the watershed. ",
         "Wait, then run tar_make() again; finished steps will be skipped.")
  }
  x
}

get_soils <- function(watershed_file) {
  ws  <- sf::st_transform(sf::st_read(watershed_file, quiet = TRUE), 4326)
  huc <- ws$huc12[1]
  
  polys <- tryCatch(
    soilDB::SDA_spatialQuery(ws, what = "mupolygon", geomIntersection = FALSE),
    error = function(e) e)
  if (is.null(polys) || (is.data.frame(polys) && nrow(polys) == 0)) {
    stop("No SSURGO map units returned for HUC12 ", huc, ". Either SSURGO has no ",
         "coverage here or Soil Data Access returned nothing; if the watershed ",
         "worked before, wait and run tar_make() again.")
  }
  polys <- check_sda(polys, "soil map unit polygons", huc)
  keys <- paste(unique(polys$mukey), collapse = ",")
  
  horizons <- soilDB::SDA_query(paste0(
    "SELECT c.mukey, c.cokey, c.compname, c.compkind, c.comppct_r, c.majcompflag,
            h.hzname, h.hzdept_r, h.hzdepb_r, h.kwfact, h.kffact
     FROM component c LEFT JOIN chorizon h ON c.cokey = h.cokey
     WHERE c.mukey IN (", keys, ")
     ORDER BY c.mukey, c.comppct_r DESC, h.hzdept_r"))
  horizons <- check_sda(horizons, "component and horizon records", huc)
  
  surveys <- soilDB::SDA_query(paste0(
    "SELECT DISTINCT l.areasymbol, l.areaname, s.saverest
     FROM mapunit m
     INNER JOIN legend l ON m.lkey = l.lkey
     INNER JOIN sacatalog s ON l.areasymbol = s.areasymbol
     WHERE m.mukey IN (", keys, ")"))
  surveys <- check_sda(surveys, "survey area records", huc)
  
  mapunits <- soilDB::SDA_query(paste0(
    "SELECT mukey, musym, muname, mukind FROM mapunit WHERE mukey IN (", keys, ")"))
  mapunits <- check_sda(mapunits, "map unit records", huc)
  
  out_dir <- "1_input/soils"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  poly_file <- file.path(out_dir, paste0("ssurgo_mupolygons_huc12_", huc, ".gpkg"))
  hz_file   <- file.path(out_dir, paste0("ssurgo_horizons_huc12_", huc, ".csv"))
  sf::st_write(polys, poly_file, delete_dsn = TRUE, quiet = TRUE)
  utils::write.csv(horizons, hz_file, row.names = FALSE)
  
  meta_dir <- "1_input/source_metadata/soils"
  dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(surveys, file.path(meta_dir, "ssurgo_survey_areas.csv"), row.names = FALSE)
  utils::write.csv(mapunits, file.path(meta_dir, "ssurgo_mapunits.csv"), row.names = FALSE)
  
  log_retrieval(
    layer   = "soils",
    source  = "NRCS SSURGO via Soil Data Access (soilDB::SDA_spatialQuery, SDA_query)",
    url     = "https://sdmdataaccess.nrcs.usda.gov",
    version = paste0("Survey ", paste(surveys$areasymbol, collapse = ", "),
                     ", version date ", paste(surveys$saverest, collapse = ", "),
                     "; soilDB ", utils::packageVersion("soilDB")),
    file    = paste(poly_file, hz_file, sep = "; ")
  )
  c(poly_file, hz_file)
}