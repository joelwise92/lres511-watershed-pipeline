# Stage 3 (test): harmonize LANDFIRE forest structure onto the common grid.
#
# For each kept crosswalk row with layer forest_cc or forest_ch:
#   1. find the matching band in the LANDFIRE file (source_attribute, e.g.
#      "CC" matches band LF2024_CC_CONUS)
#   2. apply the crosswalk's multiply_by (canopy height: 0.1, decimeters to m)
#   3. resample to the common grid with nearest neighbor, because LANDFIRE
#      stores both products as classes (bilinear would invent values between
#      classes)
#   4. mask to the watershed and write to 4_product/data/

harmonize_forest <- function(forest_file, watershed_file, crosswalk_file, config) {
  ws       <- read_watershed(watershed_file, config)
  huc      <- ws$huc12[1]
  template <- make_template(ws, config)
  cw       <- utils::read.csv(crosswalk_file, colClasses = "character", na.strings = "")
  rows     <- cw[cw$layer %in% c("forest_cc", "forest_ch") & toupper(cw$keep) == "TRUE", ]
  
  tif <- grep("\\.tif$", utils::unzip(forest_file, list = TRUE)$Name, value = TRUE)[1]
  r   <- terra::rast(paste0("/vsizip/", normalizePath(forest_file, winslash = "/"), "/", tif))
  
  out_dir <- "4_product/data"
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  
  files <- vapply(seq_len(nrow(rows)), function(i) {
    row  <- rows[i, ]
    band <- grep(paste0("_", row$source_attribute, "_"), names(r), value = TRUE)
    if (length(band) != 1) {
      stop("Expected one LANDFIRE band matching '", row$source_attribute, "', found: ",
           paste(names(r), collapse = ", "))
    }
    x <- r[[band]]
    if (!is.na(row$multiply_by)) x <- x * as.numeric(row$multiply_by)
    x <- terra::project(x, template, method = "near")
    x <- terra::mask(x, terra::vect(ws))
    names(x) <- row$layer
    out <- file.path(out_dir, paste0(row$layer, "_", huc, "_", config$resolution_m, "m.tif"))
    terra::writeRaster(x, out, filetype = "COG", datatype = "FLT4S",
                       NAflag = -9999, overwrite = TRUE)
    out
  }, character(1))
  unname(files)
}