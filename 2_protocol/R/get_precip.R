# Stage 2: precipitation frequency from NOAA Atlas 14 (partial duration series).
#
# 1. Gets NOAA's point table at the watershed center. It names the Atlas 14
#    volume that covers the watershed, records the version, and gives
#    reference values for checking the harmonized grids. Saved per watershed
#    as 1_input/source_metadata/precip/pfds_point_intensity_<huc12>.txt.
# 2. Looks up that volume's download folder in 2_protocol/atlas14_volumes.csv
#    (or uses config$precip$volume_prefix if it is set to a folder code).
# 3. Downloads the grids listed in the config as the original zip files,
#    unchanged, to 1_input/precip/.
#
# Existing files are reused: the point table for this watershed and any grid
# zips already downloaded. A watershed whose files all exist needs no web
# access at all. To force fresh downloads, delete the files or set
# refresh = TRUE.
#
# NOAA's server is retried after pauses if it does not respond, then stops
# with a clear outage message.
#
# Config settings (study_area.yml):
#   precip:
#     volume_prefix: "auto"      # or a folder code such as "inw" to override
#     ari_years: 2               # return period in years
#     durations: ["30m", "60m", "06h"]

# Read a URL, retrying after pauses if the server does not respond.
read_with_retry <- function(url, attempts = 3, wait_s = 20) {
  for (a in seq_len(attempts)) {
    result <- tryCatch(readLines(url, warn = FALSE), error = function(e) e,
                       warning = function(w) w)
    if (is.character(result)) return(result)
    if (a < attempts) Sys.sleep(wait_s * a)
  }
  stop("NOAA's precipitation frequency service is not responding (",
       conditionMessage(result), "). This is a NOAA outage, not a problem with the ",
       "watershed. Wait, then run tar_make() again; finished steps will be skipped.")
}

get_precip <- function(watershed_file, config, volumes_file, refresh = FALSE) {
  ws   <- sf::st_read(watershed_file, quiet = TRUE)
  huc  <- ws$huc12[1]
  ari  <- config$precip$ari_years
  durs <- unlist(config$precip$durations)
  
  meta_dir <- "1_input/source_metadata/precip"
  out_dir  <- "1_input/precip"
  dir.create(meta_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  pf_file  <- file.path(meta_dir, paste0("pfds_point_intensity_", huc, ".txt"))
  
  # Point table at the watershed center: reuse if saved, otherwise fetch
  fetched <- FALSE
  if (file.exists(pf_file) && !refresh) {
    pf <- readLines(pf_file, warn = FALSE)
  } else {
    ctr <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf::st_transform(ws, 4326))))
    pf_url <- paste0("https://hdsc.nws.noaa.gov/cgi-bin/hdsc/new/fe_text_mean.csv?lat=",
                     round(ctr[2], 5), "&lon=", round(ctr[1], 5),
                     "&data=intensity&units=metric&series=pds")
    pf <- read_with_retry(pf_url)
    fetched <- TRUE
  }
  
  version <- grep("NOAA Atlas 14", pf, value = TRUE)[1]
  if (is.na(version)) {
    stop("NOAA Atlas 14 has no coverage at HUC12 ", huc,
         " (for example, Oregon and Washington). See the decision log.")
  }
  if (fetched) writeLines(pf, pf_file)
  
  # Which download folder holds this volume's grids
  vol <- config$precip$volume_prefix
  if (is.null(vol) || vol == "auto") {
    vol_num <- as.integer(sub(".*Volume ([0-9]+).*", "\\1", version))
    volumes <- utils::read.csv(volumes_file, stringsAsFactors = FALSE)
    vol <- volumes$folder[volumes$volume == vol_num]
    if (length(vol) != 1) {
      stop("Atlas 14 Volume ", vol_num, " is not in ", volumes_file,
           ". Add its download folder after checking it on the NOAA site.")
    }
  }
  base <- paste0("https://hdsc.nws.noaa.gov/pub/hdsc/data/", vol)
  
  # Grid zips can be large, so allow more time than R's 60-second default
  old <- options(timeout = max(600, getOption("timeout")))
  on.exit(options(old))
  
  downloaded <- FALSE
  files <- vapply(durs, function(d) {
    name <- sprintf("%s%syr%sa.zip", vol, ari, d)
    dest <- file.path(out_dir, name)
    if (!file.exists(dest) || refresh) {
      utils::download.file(paste0(base, "/", name), dest, mode = "wb", quiet = TRUE)
      downloaded <<- TRUE
    }
    dest
  }, character(1))
  
  # Log only when something was actually downloaded
  if (fetched || downloaded) {
    log_retrieval(
      layer   = "precip",
      source  = "NOAA Atlas 14 precipitation frequency grids, partial duration series (PFDS)",
      url     = paste(paste0(base, "/", basename(files)), collapse = "; "),
      version = paste0(version, " (folder ", vol, "); ", ari, "-year ARI; durations ",
                       paste(durs, collapse = ", ")),
      file    = paste(c(files, pf_file), collapse = "; ")
    )
  } else {
    message("Using existing precipitation downloads for HUC12 ", huc)
  }
  unname(files)
}