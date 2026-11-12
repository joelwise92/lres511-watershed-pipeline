# Stage 3 (test): annual disturbance history from LANDFIRE.
#
# 1. Downloads LANDFIRE's attribute tables for every Annual Disturbance
#    year (one zip of CSVs). Product names, which follow no fixed pattern,
#    come from 2_protocol/landfire_dist_products.csv.
# 2. Requests the final annual disturbance products for the years in the
#    config, in batches, for the watershed plus a 1 km buffer, in the
#    output CRS. Each batch's zip is saved unchanged to 1_input/disturbance/.
#
# Existing downloads are reused; delete them or set refresh = TRUE to
# request again.
#
# Config settings (study_area.yml):
#   disturbance:
#     start_year: 1999
#     end_year: 2025
#     tables_url: "https://landfire.gov/sites/default/files/CSV/AllYears/DistCSV_AllYears.zip?release=R5"
# The LANDFIRE email is taken from config$forest$email.

# Year-to-product table: product names come from the protocol file
# 2_protocol/landfire_dist_products.csv (verified against LANDFIRE's product
# table), and each year's attribute table is matched by year from the
# attribute-table download. The attribute file names do not always match
# the product names (2008 is LF2010_Dist08 in the tables but LF2008_Dist08
# in the product service), so they are not used for product names.
dist_products <- function(tables_zip, products_file) {
  prods <- utils::read.csv(products_file, stringsAsFactors = FALSE)
  names <- basename(utils::unzip(tables_zip, list = TRUE)$Name)
  m <- regmatches(names, regexec("^LF[0-9]{4}_Dist([0-9]{2})_([0-9]{8})\\.csv$", names))
  m <- m[lengths(m) == 3]
  tabs <- data.frame(
    csv        = vapply(m, `[`, "", 1),
    yy         = as.integer(vapply(m, `[`, "", 2)),
    table_date = vapply(m, `[`, "", 3),
    stringsAsFactors = FALSE
  )
  tabs$year <- ifelse(tabs$yy >= 90, 1900 + tabs$yy, 2000 + tabs$yy)
  # If a year has more than one table version, keep the newest
  tabs <- tabs[order(tabs$year, tabs$table_date), ]
  tabs <- tabs[!duplicated(tabs$year, fromLast = TRUE), c("year", "table_date", "csv")]
  merge(prods[, c("year", "product")], tabs, by = "year", all.x = TRUE)
}

get_disturbance <- function(watershed_file, config, products_file,
                            refresh = FALSE, batch_size = 10) {
  ws  <- sf::st_read(watershed_file, quiet = TRUE)
  huc <- ws$huc12[1]
  cfg <- config$disturbance
  years <- seq(cfg$start_year, cfg$end_year)
  
  out_dir <- "1_input/disturbance"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Attribute tables (all years); shared by every watershed
  tables_zip <- file.path(out_dir, "landfire_DistCSV_AllYears.zip")
  if (!file.exists(tables_zip) || refresh) {
    old <- options(timeout = max(600, getOption("timeout")))
    on.exit(options(old), add = TRUE)
    utils::download.file(cfg$tables_url, tables_zip, mode = "wb", quiet = TRUE)
  }
  prods <- dist_products(tables_zip, products_file)
  missing <- setdiff(years, prods$year[!is.na(prods$csv)])
  if (length(missing) > 0) {
    stop("No LANDFIRE Annual Disturbance product or attribute table for year(s) ",
         paste(missing, collapse = ", "), ". Add the year to ", products_file,
         " (after checking the product name in LANDFIRE's product table), or adjust ",
         "start_year or end_year in the config.")
  }
  prods <- prods[prods$year %in% years, ]
  
  # Request in batches
  batches <- split(prods, ceiling(seq_len(nrow(prods)) / batch_size))
  aoi <- NULL
  downloaded <- FALSE
  files <- vapply(batches, function(b) {
    f <- file.path(out_dir, sprintf("landfire_dist_%d_%d_huc12_%s.zip",
                                    min(b$year), max(b$year), huc))
    if (file.exists(f) && !refresh) return(f)
    if (is.null(aoi)) aoi <<- rlandfire::getAOI(sf::st_transform(ws, config$crs), extend = 1000)
    resp <- rlandfire::landfireAPIv2(products = b$product, aoi = aoi,
                                     email = config$forest$email, projection = config$crs,
                                     path = tempfile(fileext = ".zip"))
    if (is.null(resp$path) || !file.exists(resp$path)) {
      stop("The LANDFIRE disturbance request for ", min(b$year), "-", max(b$year),
           " did not return a file. The LANDFIRE Product Service may be busy or down; ",
           "wait and run tar_make() again.")
    }
    file.copy(resp$path, f, overwrite = TRUE)
    downloaded <<- TRUE
    f
  }, character(1))
  files <- unname(files)
  
  meta_dir <- "1_input/source_metadata/disturbance"
  dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(prods, file.path(meta_dir, paste0("dist_products_", huc, ".csv")), row.names = FALSE)
  
  if (downloaded) {
    log_retrieval(
      layer   = "disturbance",
      source  = "LANDFIRE Annual Disturbance (final) via rlandfire::landfireAPIv2(); attribute tables from landfire.gov",
      url     = paste("https://lfps.usgs.gov;", cfg$tables_url),
      version = paste0(min(years), "-", max(years), "; products ",
                       paste(prods$product, collapse = ", "), "; attribute tables dated ",
                       paste(unique(prods$table_date), collapse = ", "),
                       "; rlandfire ", utils::packageVersion("rlandfire")),
      file    = paste(c(files, tables_zip), collapse = "; ")
    )
  } else {
    message("Using existing LANDFIRE disturbance downloads for HUC12 ", huc)
  }
  # Disturbance zips first (the catalog describes the first file), tables last
  c(files, tables_zip)
}