# Testing helper: pick a random HUC12 in the lower 48 states.
#
# Draws random points in the lower 48 bounding box until one lands in a
# watershed the pipeline should handle. Skips points in the ocean, in
# open-water units (such as the Great Lakes), in watersheds that cross
# into Canada or Mexico, and in states without NOAA Atlas 14 coverage.
# Used by run.R when huc12 is set to "random". Not part of the pipeline.

random_huc12 <- function(exclude_states = c("OR", "WA")) {
  repeat {
    lon <- stats::runif(1, -124.7, -67.0)
    lat <- stats::runif(1, 24.5, 49.4)
    hu  <- tryCatch(find_huc12(lon, lat), error = function(e) NULL)
    if (is.null(hu) || nrow(hu) == 0) next
    st <- trimws(strsplit(hu$states[1], ",")[[1]])
    if (any(st %in% c(exclude_states, "CN", "MX"))) next
    if (hu$hutype[1] == "W") next
    return(data.frame(huc12 = hu$huc12[1], name = hu$name[1], states = hu$states[1],
                      lon = round(lon, 4), lat = round(lat, 4)))
  }
}