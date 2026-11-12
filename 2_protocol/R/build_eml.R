# Standards-based metadata: Ecological Metadata Language (EML) for the
# final dataset, written to 4_product/eml.xml and validated against the
# EML schema.
#
# Assembled from files the pipeline already maintains:
#   - data dictionary: attribute names, definitions, units, data types
#   - layer catalog: source, version, retrieval date, and processing
#     for each layer (becomes the methods / provenance section)
#   - watershed boundary: geographic coverage
# plus 2_protocol/eml_settings.yml for the title, abstract, creator,
# keywords, and usage rights.
#
# Each final file is described as an EML "otherEntity" with its format,
# size, MD5 checksum, and attribute list. Raster attributes declare the
# -9999 NoData value, coded variables list their codes, and the dataset
# carries a revision number and change history from 2_protocol/changelog.csv.

# Units used in the data dictionary, mapped to EML unit names. Units not
# in EML's standard dictionary are defined in custom_units below.
eml_unit_map <- c(
  "m"                       = "meter",
  "km"                      = "kilometer",
  "km2"                     = "squareKilometer",
  "m/m"                     = "meterPerMeter",
  "mm/hr"                   = "millimeterPerHour",
  "%"                       = "percent",
  "year"                    = "nominalYear",
  "K-factor (US customary)" = "kFactorUSCustomary"
)

custom_units <- data.frame(
  id             = c("squareKilometer", "meterPerMeter", "millimeterPerHour",
                     "percent", "kFactorUSCustomary"),
  unitType       = c("area", "dimensionless", "speed", "dimensionless", "dimensionless"),
  parentSI       = c("squareMeter", "dimensionless", "metersPerSecond", "dimensionless",
                     "dimensionless"),
  multiplierToSI = c("1000000", "1", "0.0000002777778", "0.01", "1"),
  description    = c("square kilometer",
                     "meters of elevation change per meter of distance",
                     "millimeters per hour",
                     "percent",
                     paste("soil erodibility K-factor in US customary units",
                           "(ton acre hour per hundred acre foot ton-force inch);",
                           "listed as dimensionless only for EML unit typing")),
  stringsAsFactors = FALSE
)

# Coded variables: each code and its definition, written to EML as an
# enumerated domain instead of a number with units. Add a block here for
# any new coded layer.
eml_code_lists <- data.frame(
  attributeName = "dist_last_severity",
  code          = c("0", "1", "2", "3"),
  definition    = c(
    paste("No severity class: disturbed, but the LANDFIRE SEVERITY label is not a",
          "severity class (e.g. No Severity, Increased Green, blank)"),
    paste("Low: LANDFIRE SEVERITY label beginning with Low or Unburned",
          "(e.g. Low, Low-Medium, Unburned/Low)"),
    paste("Medium: LANDFIRE SEVERITY label beginning with Medium or Moderate",
          "(e.g. Medium, Medium-High, Moderate, Moderate-Low, Moderate-High)"),
    "High: LANDFIRE SEVERITY label beginning with High"),
  stringsAsFactors = FALSE
)

# Changelog columns: revision (integer), date (YYYY-MM-DD), scope (what
# changed, e.g. "soils layer"), change (one-sentence description).
read_changelog <- function(changelog_file) {
  if (!file.exists(changelog_file)) return(NULL)
  # UTF-8-BOM handles files saved by Excel
  cl <- utils::read.csv(changelog_file, stringsAsFactors = FALSE,
                        fileEncoding = "UTF-8-BOM")
  if (nrow(cl) == 0) return(NULL)
  # Excel rewrites 2026-10-21 as 10/21/2026 when it saves a CSV, so accept
  # either and convert to the YYYY-MM-DD form EML requires
  parse_date <- function(x) {
    for (f in c("%Y-%m-%d", "%m/%d/%Y")) {
      d <- as.Date(trimws(x), format = f)
      if (!is.na(d)) return(format(d, "%Y-%m-%d"))
    }
    NA_character_
  }
  cl$date <- vapply(as.character(cl$date), parse_date, character(1), USE.NAMES = FALSE)
  bad <- is.na(cl$date)
  if (any(bad)) stop("Unreadable dates in ", changelog_file, " (use YYYY-MM-DD); ",
                     "check revision(s) ", paste(cl$revision[bad], collapse = ", "))
  cl[order(cl$revision), ]
}

build_eml <- function(dictionary_file, catalog_file, settings_file,
                      watershed_file, files, config,
                      changelog_file = "2_protocol/changelog.csv") {
  dict     <- utils::read.csv(dictionary_file, stringsAsFactors = FALSE)
  catalog  <- utils::read.csv(catalog_file, stringsAsFactors = FALSE)
  settings <- yaml::read_yaml(settings_file)
  
  # Stop if the settings still have placeholders
  who <- unlist(settings$creator)
  if (any(grepl("^\\[", who))) {
    stop("Fill in the creator details in ", settings_file, " before building EML metadata.")
  }
  
  ws    <- sf::st_read(watershed_file, quiet = TRUE)
  bb    <- sf::st_bbox(sf::st_transform(ws, 4326))
  huc   <- ws$huc12[1]
  wname <- ws$watershed_name[1]
  
  changelog <- read_changelog(changelog_file)
  revision  <- if (is.null(changelog)) 1L else max(changelog$revision)
  
  # Attribute list for one layer, from the data dictionary
  make_attributes <- function(layer, is_raster) {
    d <- dict[dict$layer == layer, ]
    if (nrow(d) == 0) stop("No data dictionary rows for layer ", layer)
    d$units[is.na(d$units)] <- ""
    # Identifiers and codes are labels, not quantities, even when stored as
    # numbers (e.g. nhdplus_id, hydro_seq, feature_code): describe them as text
    is_id <- grepl("(_id|_seq|_code)$", d$variable)
    is_coded <- d$variable %in% eml_code_lists$attributeName
    cls  <- ifelse(is_coded, "factor",
                   ifelse(d$data_type == "character" | is_id, "character",
                          ifelse(d$data_type == "Date", "Date", "numeric")))
    unit <- ifelse(cls != "numeric", NA,
                   ifelse(d$units == "", "dimensionless", unname(eml_unit_map[d$units])))
    missing_unit <- cls == "numeric" & is.na(unit)
    if (any(missing_unit)) {
      stop("No EML unit for: ", paste(unique(d$units[missing_unit]), collapse = ", "),
           ". Add it to eml_unit_map (and custom_units if needed) in build_eml.R.")
    }
    d$units[is_id] <- ""
    attrs <- data.frame(
      attributeName       = d$variable,
      attributeDefinition = d$description,
      unit                = unit,
      numberType          = ifelse(cls == "numeric",
                                   ifelse(d$data_type == "integer", "integer", "real"), NA),
      formatString        = ifelse(cls == "Date", "YYYY-MM-DD", NA),
      definition          = ifelse(cls == "character", d$description, NA),
      stringsAsFactors    = FALSE
    )
    # Rasters store NoData as -9999 (vector layers use true NULLs instead)
    if (is_raster) {
      attrs$missingValueCode            <- "-9999"
      attrs$missingValueCodeExplanation <- paste("NoData: cell outside the watershed",
                                                 "boundary or no source value")
    }
    codes <- eml_code_lists[eml_code_lists$attributeName %in% d$variable, ]
    # EML warns about every unit not in its standard dictionary. Those units
    # are defined in custom_units (written to the file's unitList), so that
    # specific reminder is muffled; any other warning still shows.
    withCallingHandlers(
      EML::set_attributes(attrs, factors = if (nrow(codes) > 0) codes else NULL,
                          col_classes = cls),
      warning = function(w) {
        if (grepl("not a recognized standard unit", conditionMessage(w))) {
          invokeRestart("muffleWarning")
        }
      }
    )
  }
  
  # One entity per final file
  make_entity <- function(layer, file) {
    is_raster <- grepl("\\.tif$", file)
    fmt <- if (is_raster) "GeoTIFF (cloud-optimized)" else "GeoPackage"
    list(
      entityName        = basename(file),
      entityDescription = paste0(if (is_raster) "Raster" else "Vector", " layer '", layer,
                                 "' for HUC12 ", huc, "; EPSG:", config$crs,
                                 if (is_raster) paste0("; ", config$resolution_m, " m grid") else ""),
      physical = list(
        objectName     = basename(file),
        size           = list(unit = "bytes", size = as.character(file.size(file))),
        authentication = list(method = "MD5", authentication = unname(tools::md5sum(file))),
        dataFormat     = list(externallyDefinedFormat = list(formatName = fmt))
      ),
      attributeList = make_attributes(layer, is_raster),
      entityType    = fmt
    )
  }
  
  # Methods: an overview, then one step per layer from the layer catalog
  steps <- lapply(seq_len(nrow(catalog)), function(i) {
    list(description = list(para = paste0(
      catalog$layer[i], ": ", catalog$source[i], " (", catalog$source_url[i], "). ",
      "Version: ", catalog$version[i], ". Retrieved: ", catalog$retrieved[i], ". ",
      "Raw file MD5: ", catalog$source_md5[i], ". ",
      "Processing: ", catalog$processing[i], " ",
      "Scripts: ", catalog$scripts[i], ".")))
  })
  overview <- paste0(settings$methods_overview, " Pipeline code version: ",
                     catalog$code_version[1], ".")
  methods <- list(methodStep = c(list(list(description = list(para = overview))),
                                 steps))
  
  # Maintenance: revision number and one changeHistory entry per revision
  maintenance <- list(description = list(para = paste0(
    "Revision ", revision, ". The dataset is rebuilt by rerunning the pipeline; ",
    "each revision is logged in ", changelog_file, " with its date and what changed.")))
  if (!is.null(changelog)) {
    maintenance$changeHistory <- lapply(seq_len(nrow(changelog)), function(i) list(
      changeScope = changelog$scope[i],
      oldValue    = if (changelog$revision[i] <= 1) "none (first release)"
      else paste("revision", changelog$revision[i] - 1),
      changeDate  = changelog$date[i],
      comment     = paste0("Revision ", changelog$revision[i], ": ", changelog$change[i])
    ))
  }
  
  creator <- list(
    individualName        = list(givenName = settings$creator$given_name,
                                 surName   = settings$creator$sur_name),
    organizationName      = settings$creator$organization,
    electronicMailAddress = settings$creator$email
  )
  
  dataset <- list(
    title              = paste0(settings$title, ": ", wname, " (HUC12 ", huc, ")"),
    creator            = creator,
    pubDate            = format(Sys.Date()),
    abstract           = list(para = settings$abstract),
    keywordSet         = list(list(keyword = as.list(settings$keywords))),
    intellectualRights = list(para = settings$intellectual_rights),
    coverage = list(geographicCoverage = list(
      geographicDescription = paste0(wname, " watershed (HUC12 ", huc, "), ", ws$states[1]),
      boundingCoordinates = list(
        westBoundingCoordinate  = as.character(round(bb[["xmin"]], 5)),
        eastBoundingCoordinate  = as.character(round(bb[["xmax"]], 5)),
        northBoundingCoordinate = as.character(round(bb[["ymax"]], 5)),
        southBoundingCoordinate = as.character(round(bb[["ymin"]], 5))
      )
    )),
    maintenance = maintenance,
    contact     = creator,
    methods     = methods,
    otherEntity = mapply(make_entity, names(files), files, SIMPLIFY = FALSE, USE.NAMES = FALSE)
  )
  
  eml <- list(
    packageId          = paste0("huc12-", huc, "-harmonized.", revision),
    system             = "local",
    dataset            = dataset,
    additionalMetadata = list(metadata = list(unitList = EML::set_unitList(custom_units)))
  )
  
  out_file <- "4_product/eml.xml"
  EML::write_eml(eml, out_file)
  
  valid <- EML::eml_validate(out_file)
  if (!isTRUE(valid)) {
    stop("EML metadata did not validate:\n", paste(attr(valid, "errors"), collapse = "\n"))
  }
  out_file
}