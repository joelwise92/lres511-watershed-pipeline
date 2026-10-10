# Metadata: layer catalog (built automatically by the pipeline) and a
# helper for drafting the attribute crosswalk (run once in the Console).

# Describe a raster or vector file: type, CRS, resolution, and size.
describe_layer <- function(file) {
  if (grepl("\\.tif$", file)) {
    r   <- terra::rast(file)
    crs <- terra::crs(r, describe = TRUE)
    list(
      type       = "raster",
      crs        = paste0(crs$authority, ":", crs$code, " (", crs$name, ")"),
      resolution = paste(signif(terra::res(r), 6), collapse = " x "),
      size       = paste(terra::nrow(r), "rows x", terra::ncol(r), "cols")
    )
  } else {
    v   <- sf::st_read(file, quiet = TRUE)
    crs <- sf::st_crs(v)
    list(
      type       = paste("vector", as.character(sf::st_geometry_type(v, by_geometry = FALSE))),
      crs        = paste0("EPSG:", crs$epsg, " (", crs$Name, ")"),
      resolution = NA_character_,
      size       = paste(nrow(v), "features")
    )
  }
}

# How each layer was processed during harmonization. Update this when a
# harmonization step changes.
processing_notes <- c(
  watershed_boundary = "Reprojected to output CRS; attributes renamed and converted per crosswalk.",
  dem     = "Reprojected and resampled (bilinear) to common grid; masked to watershed; NoData = -9999.",
  streams = "Reprojected to output CRS; clipped to watershed; attributes renamed and converted per crosswalk."
)

# Build the layer catalog: one row per layer, combining the retrieval log
# (source, version, date) with properties of the raw and harmonized files.
# raw and harmonized are named vectors of file paths; names must match the
# layer names used in the retrieval log.
build_layer_catalog <- function(raw, harmonized,
                                log_path = "1_input/retrieval_log.csv") {
  log <- utils::read.csv(log_path, stringsAsFactors = FALSE)
  
  rows <- lapply(names(raw), function(layer) {
    entry <- utils::tail(log[log$layer == layer, ], 1)  # most recent download
    nat   <- describe_layer(raw[[layer]])
    out   <- describe_layer(harmonized[[layer]])
    data.frame(
      layer              = layer,
      source             = entry$source,
      source_url         = entry$url,
      version            = entry$version,
      retrieved          = entry$retrieved,
      data_type          = out$type,
      native_crs         = nat$crs,
      native_resolution  = nat$resolution,
      output_crs         = out$crs,
      output_resolution  = out$resolution,
      output_size        = out$size,
      processing         = unname(processing_notes[layer]),
      raw_file           = raw[[layer]],
      harmonized_file    = harmonized[[layer]],
      stringsAsFactors   = FALSE
    )
  })
  catalog <- do.call(rbind, rows)
  
  out_file <- "4_product/layer_catalog.csv"
  utils::write.csv(catalog, out_file, row.names = FALSE)
  out_file
}

# Console helper (not part of the pipeline): list every attribute in the
# raw vector layers, with its type and an example value, as a starting
# point for the crosswalk. Fill in the blank columns, then save the result
# as 2_protocol/crosswalk.csv.
draft_crosswalk <- function(files, out_file = "2_protocol/crosswalk_draft.csv") {
  rows <- lapply(names(files), function(layer) {
    d <- sf::st_drop_geometry(sf::st_read(files[[layer]], quiet = TRUE))
    data.frame(
      layer            = layer,
      source_attribute = names(d),
      source_type      = vapply(d, function(x) class(x)[1], character(1)),
      example_value    = vapply(d, function(x) {
        x <- x[!is.na(x)]
        if (length(x) == 0) NA_character_ else substr(as.character(x[1]), 1, 40)
      }, character(1)),
      keep             = "",
      harmonized_name  = "",
      units            = "",
      description      = "",
      stringsAsFactors = FALSE
    )
  })
  draft <- do.call(rbind, rows)
  utils::write.csv(draft, out_file, row.names = FALSE)
  message("Wrote ", nrow(draft), " attributes to ", out_file)
  invisible(draft)
}

# Build the data dictionary: one row per variable in the final dataset,
# combining the crosswalk (names, units, descriptions, processing) with
# the actual values in the final files (data type, range, missing count).
# files is a named vector of final file paths; names match crosswalk layers.
build_data_dictionary <- function(crosswalk_file, files) {
  cw <- utils::read.csv(crosswalk_file, colClasses = "character", na.strings = "")
  cw <- cw[toupper(cw$keep) == "TRUE", ]
  
  # Summarize one vector of values: data type, range, and missing count
  summarize_values <- function(x) {
    type <- class(x)[1]
    rng <- if (is.numeric(x) || inherits(x, "Date")) {
      if (all(is.na(x))) NA_character_
      else paste(format(min(x, na.rm = TRUE)), "to", format(max(x, na.rm = TRUE)))
    } else {
      paste(length(unique(stats::na.omit(x))), "distinct values")
    }
    list(type = type, range = rng, n_missing = sum(is.na(x)))
  }
  
  rows <- lapply(seq_len(nrow(cw)), function(i) {
    row  <- cw[i, ]
    file <- files[[row$layer]]
    
    if (grepl("\\.tif$", file)) {
      r    <- terra::rast(file)
      mm   <- terra::global(r, c("min", "max"), na.rm = TRUE)
      vals <- list(type = "numeric (raster)",
                   range = paste(signif(mm$min, 6), "to", signif(mm$max, 6)),
                   n_missing = NA_integer_)
    } else {
      d    <- sf::st_drop_geometry(sf::st_read(file, quiet = TRUE))
      vals <- summarize_values(d[[row$harmonized_name]])
    }
    
    steps <- c(
      if (!identical(row$source_attribute, row$harmonized_name))
        paste0("renamed from ", row$source_attribute),
      if (!is.na(row$nodata_source)) paste0("source NoData ", row$nodata_source, " set to NA"),
      if (!is.na(row$multiply_by))   paste0("multiplied by ", row$multiply_by,
                                            " (", row$source_units, " to ", row$units, ")"),
      if (!is.na(row$units) && row$units == "date") "converted to date"
    )
    
    data.frame(
      variable         = row$harmonized_name,
      layer            = row$layer,
      description      = row$description,
      units            = ifelse(is.na(row$units), "", row$units),
      data_type        = vals$type,
      range            = vals$range,
      n_missing        = vals$n_missing,
      source_attribute = row$source_attribute,
      processing       = paste(steps, collapse = "; "),
      stringsAsFactors = FALSE
    )
  })
  dictionary <- do.call(rbind, rows)
  
  out_file <- "4_product/data_dictionary.csv"
  utils::write.csv(dictionary, out_file, row.names = FALSE)
  out_file
}