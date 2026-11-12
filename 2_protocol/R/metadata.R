# Metadata: layer catalog (built automatically by the pipeline) and a
# helper for drafting the attribute crosswalk

# Describe a raster or vector file: type, CRS, resolution, and size.
describe_layer <- function(file) {
  # Grids inside zip archives (e.g. NOAA Atlas 14) are read in place
  if (grepl("\\.zip$", file)) {
    asc  <- grep("\\.(asc|tif)$", utils::unzip(file, list = TRUE)$Name, value = TRUE)[1]
    file <- paste0("/vsizip/", normalizePath(file, winslash = "/"), "/", asc)
  }
  if (grepl("\\.(tif|asc)$", file)) {
    r   <- terra::rast(file)
    crs <- terra::crs(r, describe = TRUE)
    list(
      type       = "raster",
      crs        = if (terra::crs(r) == "") "not defined in source file"
      else paste0(crs$authority, ":", crs$code, " (", crs$name, ")"),
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
# harmonization step changes, and add a row to 2_protocol/changelog.csv.
# These notes are copied into the EML, which reads anything in angle
# brackets as an XML tag, so don't use < or > in them.
processing_notes <- c(
  watershed_boundary = "Reprojected to output CRS; attributes renamed and converted per crosswalk.",
  dem     = paste("Reprojected and resampled (bilinear) to common grid; masked to watershed;",
                  "no pit or flat filling; elevations keep the source vertical datum (see",
                  "version); NoData = -9999."),
  streams = "Reprojected to output CRS; clipped to watershed; attributes renamed and converted per crosswalk.",
  soils   = paste("Component K from first horizon with a value; map unit K as component-percent",
                  "weighted mean of components with K (kwfact and kffact separately); percent of",
                  "map unit without K recorded; polygons rasterized to common grid (cell centers);",
                  "masked to watershed; NoData = -9999."),
  precip  = paste("Grids read from original zips; NAD83 geographic assigned where the grid has",
                  "no CRS; cropped to watershed + 2 km; depth (0.001 in) converted to intensity",
                  "(mm/hr) using crosswalk factors; resampled (bilinear) from ~800 m to common",
                  "grid; masked to watershed; NoData = -9999."),
  forest  = paste("LANDFIRE products requested in output CRS; canopy height converted from",
                  "decimeters to meters; resampled from 30 m to common grid with nearest",
                  "neighbor (classed values); masked to watershed; NoData = -9999."),
  disturbance = paste("Annual codes translated with each year's own LANDFIRE attribute table;",
                      "LANDFIRE DIST_TYPE values grouped into harvest, fire, insect, and other per",
                      "2_protocol/dist_type_groups.csv; LANDFIRE SEVERITY labels ranked 1 (low or",
                      "unburned), 2 (medium or moderate), 3 (high) by their first word, and 0 when",
                      "the label is not a severity class (e.g. No Severity). Summarized per cell at",
                      "30 m: each group keeps its own most recent year, so a cell with insect",
                      "mortality that later burned has both an insect year and a fire year;",
                      "dist_last_severity is the severity of the most recent disturbance of any",
                      "group; dist_count is the number of years with any disturbance. Every source",
                      "label with its assigned group and rank is listed in the watershed's",
                      "4_product/data/disturbance_codes_[HUC12].csv. Resampled to common grid with",
                      "nearest neighbor; masked to watershed; NoData = -9999.")
)

# Scripts (and functions) that retrieve and process each layer. Update this
# when a layer moves to a different script.
layer_scripts <- c(
  watershed_boundary = "get_watershed.R; harmonize_grid.R (harmonize_watershed); harmonize_attributes.R",
  dem         = "get_dem.R; harmonize_grid.R (harmonize_dem)",
  streams     = "get_streams.R; harmonize_grid.R (harmonize_streams); harmonize_attributes.R",
  soils       = "get_soils.R; harmonize_soils.R",
  precip      = "get_precip.R; harmonize_precip.R",
  forest      = "get_forest.R; harmonize_forest.R",
  disturbance = "get_disturbance.R; harmonize_disturbance.R"
)

# Build the layer catalog: one row per layer, combining the retrieval log
# (source, version, date, checksum) with properties of the raw and
# harmonized files and the code that made them.
# raw and harmonized are named lists of file paths; names must match the
# layer names used in the retrieval log. A layer can have several files
# (e.g. soils); the first file of each is described, and all are listed.
build_layer_catalog <- function(raw, harmonized,
                                log_path = "1_input/retrieval_log.csv") {
  log     <- utils::read.csv(log_path, stringsAsFactors = FALSE)
  version <- code_version()
  
  rows <- lapply(names(raw), function(layer) {
    # The log row for this exact raw file (not just the newest row for the
    # layer, which may describe another watershed after testing or reuse)
    rows  <- log[log$layer == layer &
                   grepl(raw[[layer]][1], log$file, fixed = TRUE), ]
    if (nrow(rows) == 0) {
      stop("No retrieval log entry for ", raw[[layer]][1],
           ". Delete the file and rerun to download and log it again.")
    }
    entry <- utils::tail(rows, 1)
    md5   <- if (is.null(entry$md5) || is.na(entry$md5)) {
      "not recorded (downloaded before checksums were logged)"
    } else entry$md5
    nat   <- describe_layer(raw[[layer]][1])
    out   <- describe_layer(harmonized[[layer]][1])
    data.frame(
      layer              = layer,
      source             = entry$source,
      source_url         = entry$url,
      version            = entry$version,
      retrieved          = entry$retrieved,
      source_md5         = md5,
      data_type          = out$type,
      native_crs         = nat$crs,
      native_resolution  = nat$resolution,
      output_crs         = out$crs,
      output_resolution  = out$resolution,
      output_size        = out$size,
      processing         = unname(processing_notes[layer]),
      scripts            = unname(layer_scripts[layer]),
      code_version       = version,
      raw_file           = paste(raw[[layer]], collapse = "; "),
      harmonized_file    = paste(harmonized[[layer]], collapse = "; "),
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
    
    is_raster <- grepl("\\.tif$", file)
    if (is_raster) {
      r    <- terra::rast(file)
      mm   <- terra::global(r, c("min", "max"), na.rm = TRUE)
      # A layer with no values at all (e.g. no harvest recorded) gives NaN
      rng  <- if (!is.finite(mm$min)) "no values (none recorded)" else
        paste(signif(mm$min, 6), "to", signif(mm$max, 6))
      vals <- list(type = "numeric (raster)", range = rng, n_missing = NA_integer_)
    } else {
      d    <- sf::st_drop_geometry(sf::st_read(file, quiet = TRUE))
      vals <- summarize_values(d[[row$harmonized_name]])
    }
    
    steps <- c(
      # Raster values are computed from the source, not a renamed field
      if (!identical(row$source_attribute, row$harmonized_name))
        paste0(if (is_raster) "derived from " else "renamed from ", row$source_attribute),
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