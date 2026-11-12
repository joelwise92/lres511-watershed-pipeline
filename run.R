# Rebuild the full dataset and report for one watershed.
#
# 1. Set the watershed's 12-digit HUC12 code below (keep the quotes),
#    or set it to "random" to test a random watershed in the lower 48 states
# 2. Click Source (top right of the editor), or run source("run.R")

huc12 <- "random"   # Upper Tenderfoot Creek, MT is the pilot (100301030801)

# Packages first, so everything below can run on a new computer
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")
renv::restore(prompt = FALSE)

# Random test: pick a watershed and say which one
pick <- NULL
if (huc12 == "random") {
  source("2_protocol/R/utils.R")
  source("2_protocol/R/get_watershed.R")
  source("2_protocol/R/random_huc12.R")
  pick  <- random_huc12()
  huc12 <- pick$huc12
  message("Random watershed: ", pick$name, " (", pick$states, "), HUC12 ", huc12,
          " -- to rerun it, set huc12 <- \"", huc12, "\"")
}

# Write the HUC12 into the config (only if it changed), keeping the file's comments
cfg_path <- "2_protocol/config/study_area.yml"
cfg <- readLines(cfg_path)
i   <- grep("^\\s*huc12:", cfg)
new <- sub('huc12:\\s*"[0-9]*"', paste0('huc12: "', huc12, '"'), cfg[i])
if (!identical(cfg[i], new)) {
  cfg[i] <- new
  writeLines(cfg, cfg_path)
  message("Study area set to HUC12 ", huc12)
}

# Run the pipeline, keeping any error message instead of stopping
result <- tryCatch({ targets::tar_make(); "completed" },
                   error = function(e) conditionMessage(e))

# Record random tests in 2_protocol/testing_log.csv
if (!is.null(pick)) {
  log_path <- "2_protocol/testing_log.csv"
  entry <- data.frame(pick, run_at = format(Sys.time(), "%Y-%m-%d %H:%M"),
                      result = gsub("[\r\n]+", " ", result))
  write.table(entry, log_path, sep = ",", row.names = FALSE,
              col.names = !file.exists(log_path), append = file.exists(log_path))
}

if (result == "completed") {
  utils::browseURL("4_product/data_summary.html")   # open the report
} else {
  message("Pipeline stopped: ", result)
}