# Stage 2: harmonize SSURGO soils into three rasters on the common grid.
#
# Aggregation rule (see decision log):
#   1. Component K: the first horizon from the top that has a K value.
#      This skips organic (O) horizons, which have no K-factor.
#   2. Map unit K: average of component K values, weighted by component
#      percent, using only components that have K.
#   3. Percent without K: share of each map unit made up of components
#      with no K (rock outcrop, rubble land, pits, water).
# Done separately for kwfact (whole soil) and kffact (fine earth).
#
# Outputs (4_product/data/): soil_kw, soil_kf, and soil_pct_no_k rasters,
# plus a map unit table of the aggregated values.

# K value of the first horizon (by depth) that has one.
first_k <- function(k, depth) {
  v <- k[order(depth)]
  v <- v[!is.na(v)]
  if (length(v) > 0) v[1] else NA_real_
}

# Weighted mean of x by w, using only non-missing x.
weighted_k <- function(x, w) {
  has <- !is.na(x)
  if (any(has)) sum(x[has] * w[has]) / sum(w[has]) else NA_real_
}

harmonize_soils <- function(soils_files, watershed_file, config) {
  polys <- sf::st_read(soils_files[1], quiet = TRUE)
  hz    <- utils::read.csv(soils_files[2],
                           colClasses = c(mukey = "character", cokey = "character"))
  hz$kwfact <- suppressWarnings(as.numeric(hz$kwfact))
  hz$kffact <- suppressWarnings(as.numeric(hz$kffact))
  
  # Step 1: one K value per component
  comp <- do.call(rbind, lapply(split(hz, hz$cokey), function(d) {
    data.frame(mukey     = d$mukey[1],
               comppct_r = d$comppct_r[1],
               kw        = first_k(d$kwfact, d$hzdept_r),
               kf        = first_k(d$kffact, d$hzdept_r))
  }))
  
  # Steps 2 and 3: one row per map unit
  mu <- do.call(rbind, lapply(split(comp, comp$mukey), function(d) {
    data.frame(mukey    = d$mukey[1],
               k_whole  = weighted_k(d$kw, d$comppct_r),
               k_fine   = weighted_k(d$kf, d$comppct_r),
               pct_no_k = 100 * sum(d$comppct_r[is.na(d$kw)]) / sum(d$comppct_r))
  }))
  
  polys$mukey <- as.character(polys$mukey)
  polys <- merge(polys, mu, by = "mukey", all.x = TRUE)
  
  # Rasterize onto the common grid and mask to the watershed
  ws       <- read_watershed(watershed_file, config)
  huc      <- ws$huc12[1]
  template <- make_template(ws, config)
  pv       <- terra::vect(sf::st_transform(polys, config$crs))
  
  out_dir <- "4_product/data"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  layers <- c(soil_kw = "k_whole", soil_kf = "k_fine", soil_pct_no_k = "pct_no_k")
  
  files <- vapply(names(layers), function(nm) {
    r <- terra::rasterize(pv, template, field = layers[[nm]])
    r <- terra::mask(r, terra::vect(ws))
    names(r) <- nm
    f <- file.path(out_dir, paste0(nm, "_", huc, "_", config$resolution_m, "m.tif"))
    terra::writeRaster(r, f, filetype = "COG", datatype = "FLT4S",
                       NAflag = -9999, overwrite = TRUE)
    f
  }, character(1))
  
  mu_file <- file.path(out_dir, paste0("soil_mapunits_", huc, ".csv"))
  utils::write.csv(mu, mu_file, row.names = FALSE)
  
  c(unname(files), mu_file)
}