# Attribute harmonization: apply 2_protocol/crosswalk.csv to a vector layer.
#
# For each attribute marked keep = TRUE in the crosswalk, this:
#   1. recodes the source NoData value (nodata_source) to NA
#   2. converts units (multiply_by), e.g. centimeters to meters
#   3. converts dates (units = "date") to R Date values
#   4. renames the attribute to its harmonized_name
# Attributes marked keep = FALSE are dropped.
#
# Reads the reprojected, clipped layer from 3_incremental/clipped/ and
# writes the final layer to 4_product/data/.

# Read the crosswalk rows for one layer, keeping only kept attributes.
# All columns are read as text so blank cells stay blank.
read_crosswalk <- function(crosswalk_file, layer) {
  cw <- utils::read.csv(crosswalk_file, colClasses = "character", na.strings = "")
  cw[cw$layer == layer & toupper(cw$keep) == "TRUE", ]
}

# Apply one crosswalk row to one column of data.
convert_attribute <- function(x, row) {
  if (!is.na(row$nodata_source)) {
    x[!is.na(x) & x == as.numeric(row$nodata_source)] <- NA
  }
  if (!is.na(row$multiply_by)) {
    x <- x * as.numeric(row$multiply_by)
  }
  if (!is.na(row$units) && row$units == "date") {
    if (!is.na(row$source_units) && grepl("milliseconds", row$source_units)) {
      x <- as.Date(as.POSIXct(x / 1000, origin = "1970-01-01", tz = "UTC"))
    } else {
      x <- as.Date(x)
    }
  }
  x
}

harmonize_attributes <- function(in_file, crosswalk_file, layer) {
  v  <- sf::st_read(in_file, quiet = TRUE)
  cw <- read_crosswalk(crosswalk_file, layer)
  
  # Stop if the crosswalk names an attribute the data doesn't have,
  # e.g. because the provider renamed a field
  missing <- setdiff(cw$source_attribute, names(v))
  if (length(missing) > 0) {
    stop("Crosswalk attributes not found in ", layer, ": ",
         paste(missing, collapse = ", "))
  }
  
  out <- lapply(seq_len(nrow(cw)), function(i) {
    convert_attribute(v[[cw$source_attribute[i]]], cw[i, ])
  })
  names(out) <- cw$harmonized_name
  out <- sf::st_sf(as.data.frame(out), geometry = sf::st_geometry(v))
  
  out_dir <- "4_product/data"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_file <- file.path(out_dir, basename(in_file))
  sf::st_write(out, out_file, delete_dsn = TRUE, quiet = TRUE)
  out_file
}