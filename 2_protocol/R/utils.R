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

# MD5 checksum of each file in a "; "-separated list of paths, returned in
# the same order and format. A file that does not exist gives NA.
file_md5 <- function(file) {
  paths <- trimws(strsplit(file, ";", fixed = TRUE)[[1]])
  paste(unname(tools::md5sum(paths)), collapse = "; ")
}

# Logs written before checksums were added have no md5 column. Add an empty
# one so old and new rows line up. Old rows stay NA: their checksum at
# download time is unknown, and hashing the files now would record a check
# that never happened. Re-download a layer to get its checksum logged.
upgrade_log <- function(log_path) {
  log <- utils::read.csv(log_path, stringsAsFactors = FALSE)
  if (!"md5" %in% names(log)) {
    log$md5 <- NA_character_
    utils::write.csv(log, log_path, row.names = FALSE)
  }
}

# Append one row to the retrieval log each time a source is downloaded,
# including an MD5 checksum of each downloaded file.
log_retrieval <- function(layer, source, url, version, file,
                          log_path = "1_input/retrieval_log.csv") {
  entry <- data.frame(
    layer     = layer,
    source    = source,
    url       = url,
    version   = version,
    file      = file,
    retrieved = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    md5       = file_md5(file),
    stringsAsFactors = FALSE
  )
  first_entry <- !file.exists(log_path)
  if (!first_entry) upgrade_log(log_path)
  write.table(entry, log_path, sep = ",", row.names = FALSE,
              col.names = first_entry, append = !first_entry)
  invisible(entry)
}

# Version of the pipeline code: the current git commit, flagged if tracked
# files have uncommitted changes. Recorded in the layer catalog and EML so
# each product can be traced to the exact code that made it.
code_version <- function() {
  git_exe <- find_git()
  if (is.na(git_exe)) return("not under git version control (git not found)")
  git <- function(args) {
    tryCatch(suppressWarnings(system2(git_exe, args, stdout = TRUE, stderr = FALSE)),
             error = function(e) character(0))
  }
  commit <- git(c("rev-parse", "--short", "HEAD"))
  if (length(commit) == 0 || !is.null(attr(commit, "status"))) {
    return("not under git version control")
  }
  # Only code and protocol files count: the pipeline's own outputs in
  # 1_input/ and 4_product/ change on every run
  dirty <- length(git(c("status", "--porcelain", "--untracked-files=no", "--",
                        "2_protocol", "_targets.R", "run.R"))) > 0
  paste0("git commit ", commit[1], if (dirty) " (with uncommitted changes)" else "")
}

# Path to a git program: the one on the system PATH if there is one,
# otherwise the copy bundled with GitHub Desktop on Windows (newest version).
# Returns NA if neither is found.
find_git <- function() {
  on_path <- Sys.which("git")
  if (nzchar(on_path)) return(unname(on_path))
  bundled <- Sys.glob(file.path(Sys.getenv("LOCALAPPDATA"), "GitHubDesktop", "app-*",
                                "resources", "app", "git", "cmd", "git.exe"))
  if (length(bundled) > 0) return(utils::tail(sort(bundled), 1))
  NA_character_
}