# Stage 3 (test): summarize the annual disturbance history per cell.
#
# Each year's codes are translated with THAT year's LANDFIRE attribute
# table (code meanings differ between years), then grouped using
# 2_protocol/dist_type_groups.csv (harvest, fire, insect, other).
#
# Summary layers, built at LANDFIRE's 30 m and then resampled to the common
# grid with nearest neighbor (all values are years, counts, or classes):
#   dist_last_harvest_year  most recent year with a harvest-group disturbance
#   dist_last_fire_year     most recent year with a fire-group disturbance
#   dist_last_insect_year   most recent year with an insect-group disturbance
#   dist_count              number of years with any disturbance
#   dist_last_severity      severity of the most recent disturbance (0 no severity class,
#                           1 low, 2 medium or moderate, 3 high)
# Cells never disturbed are NA in the year and severity layers and 0 in dist_count.
#
# Also writes 4_product/data/disturbance_codes_<huc12>.csv: LANDFIRE's own
# DIST_TYPE and SEVERITY labels for every year, with the group and severity
# rank each was assigned, so the source definitions travel with the product.

# Severity text to rank. Mixed labels take their first word
# ("Low-Medium" -> 1, "Moderate-High" -> 2); "Unburned/Low" -> 1. Some
# LANDFIRE years label the middle class Medium and others Moderate; both rank 2.
# Any other label ("No Severity", "Increased Green", blank) ranks 0, so a
# disturbance without a severity class still replaces an older severity
# and dist_last_severity always describes the most recent disturbance.
severity_rank <- function(s) {
  s <- tolower(trimws(s))
  ifelse(grepl("^high", s), 3L,
         ifelse(grepl("^medium|^moderate", s), 2L,
                ifelse(grepl("^low|^unburned", s), 1L, 0L)))
}

harmonize_disturbance <- function(dist_files, watershed_file, groups_file,
                                  products_file, config) {
  ws       <- read_watershed(watershed_file, config)
  huc      <- ws$huc12[1]
  template <- make_template(ws, config)
  groups   <- utils::read.csv(groups_file, stringsAsFactors = FALSE)
  group_id <- c(harvest = 1L, fire = 2L, insect = 3L, other = 4L)
  
  tables_zip <- dist_files[length(dist_files)]
  dist_zips  <- dist_files[-length(dist_files)]
  prods      <- dist_products(tables_zip, products_file)
  tdir       <- tempfile(); utils::unzip(tables_zip, exdir = tdir)
  
  # All bands from all batches, one per year, sorted by year
  bands <- do.call(c, lapply(dist_zips, function(z) {
    tif <- grep("\\.tif$", utils::unzip(z, list = TRUE)$Name, value = TRUE)[1]
    terra::rast(paste0("/vsizip/", normalizePath(z, winslash = "/"), "/", tif))
  }))
  band_product <- sub("_CONUS$|_AK$|_HI$", "", names(bands))
  band_year    <- prods$year[match(band_product, prods$product)]
  if (anyNA(band_year)) stop("Could not match LANDFIRE bands to years: ",
                             paste(names(bands)[is.na(band_year)], collapse = ", "))
  bands <- bands[[order(band_year)]]; band_product <- band_product[order(band_year)]
  band_year <- sort(band_year)
  
  last <- list(harvest = NULL, fire = NULL, insect = NULL, severity = NULL)
  count <- NULL
  unknown_types <- character(0)
  codes <- vector("list", length(band_year))
  
  for (i in seq_along(band_year)) {
    y   <- band_year[i]
    csv <- prods$csv[prods$product == band_product[i]]
    csv_path <- list.files(tdir, pattern = paste0("^", csv, "$"), recursive = TRUE,
                           full.names = TRUE)[1]
    tab <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
    tab <- tab[tab$VALUE > 0, ]
    grp <- groups$group[match(tab$DIST_TYPE, groups$dist_type)]
    unknown_types <- c(unknown_types, setdiff(tab$DIST_TYPE[is.na(grp)], "No Disturbance"))
    in_groups <- !is.na(grp)
    grp[is.na(grp)] <- "other"
    
    # Record LANDFIRE's own labels next to the group and rank they were given
    codes[[i]] <- data.frame(
      year           = y,
      product        = band_product[i],
      attribute_csv  = csv,
      value          = tab$VALUE,
      dist_type      = tab$DIST_TYPE,
      severity       = tab$SEVERITY,
      group          = grp,
      in_groups_file = in_groups,
      severity_rank  = severity_rank(tab$SEVERITY),
      stringsAsFactors = FALSE
    )
    
    x   <- bands[[i]]
    g   <- terra::classify(x, cbind(tab$VALUE, group_id[grp]), others = NA)
    sev <- terra::classify(x, cbind(tab$VALUE, severity_rank(tab$SEVERITY)), others = NA)
    any_dist <- !is.na(g)
    
    for (nm in c("harvest", "fire", "insect")) {
      yr <- terra::ifel(g == group_id[[nm]], y, NA)
      last[[nm]] <- if (is.null(last[[nm]])) yr else terra::cover(yr, last[[nm]])
    }
    last$severity <- if (is.null(last$severity)) sev else terra::cover(sev, last$severity)
    count <- if (is.null(count)) terra::ifel(any_dist, 1, 0) else count + terra::ifel(any_dist, 1, 0)
  }
  if (length(unknown_types) > 0) {
    warning("Disturbance types not in ", groups_file, " (treated as 'other'): ",
            paste(unique(unknown_types), collapse = ", "))
  }
  
  layers <- list(dist_last_harvest_year = last$harvest, dist_last_fire_year = last$fire,
                 dist_last_insect_year = last$insect, dist_count = count,
                 dist_last_severity = last$severity)
  
  out_dir <- "4_product/data"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Code lookup: every LANDFIRE value, DIST_TYPE, and SEVERITY label used in
  # the summary, with the group and severity rank assigned to it. Returned
  # last, after the five rasters, so targets tracks it and the layer catalog
  # lists it as a harmonized file.
  code_file <- file.path(out_dir, paste0("disturbance_codes_", huc, ".csv"))
  utils::write.csv(do.call(rbind, codes), code_file, row.names = FALSE)
  
  files <- vapply(names(layers), function(nm) {
    r <- terra::project(layers[[nm]], template, method = "near")
    r <- terra::mask(r, terra::vect(ws))
    names(r) <- nm
    f <- file.path(out_dir, paste0(nm, "_", huc, "_", config$resolution_m, "m.tif"))
    terra::writeRaster(r, f, filetype = "COG", datatype = "INT2S", NAflag = -9999, overwrite = TRUE)
    f
  }, character(1))
  c(unname(files), code_file)
}