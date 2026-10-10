# Shared helper functions used across the pipeline.

# Read and check the study area configuration file.
read_config <- function(path) {
  cfg <- yaml::read_yaml(path)
  huc <- cfg$study_area$huc12

  if (identical(huc, "000000000000")) {
    stop("Set study_area$huc12 in ", path, " before running the pipeline.")
  }
  if (!grepl("^[0-9]{12}$", huc)) {
    stop("study_area$huc12 must be a 12-digit code, got: ", huc)
  }
  cfg
}

# Append one row to the retrieval log each time a source is downloaded.
log_retrieval <- function(layer, source, url, version, file,
                          log_path = "1_input/retrieval_log.csv") {
  entry <- data.frame(
    layer     = layer,
    source    = source,
    url       = url,
    version   = version,
    file      = file,
    retrieved = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    stringsAsFactors = FALSE
  )
  first_entry <- !file.exists(log_path)
  write.table(entry, log_path, sep = ",", row.names = FALSE,
              col.names = first_entry, append = !first_entry)
  invisible(entry)
}
