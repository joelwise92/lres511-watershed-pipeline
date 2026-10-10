# Pipeline definition. Run with targets::tar_make() from the project root.
library(targets)
library(tarchetypes)

tar_option_set(packages = c("sf", "yaml", "nhdplusTools", "terra"))

# Load every function in 2_protocol/R
tar_source("2_protocol/R")

list(
  # Config and crosswalk are tracked, so editing either reruns what depends on it
  tar_target(config_file, "2_protocol/config/study_area.yml", format = "file"),
  tar_target(config, read_config(config_file)),
  tar_target(crosswalk_file, "2_protocol/crosswalk.csv", format = "file"),
  
  # Stage 1 acquisition
  tar_target(watershed_file, get_watershed(config), format = "file"),
  tar_target(dem_file, get_dem(watershed_file), format = "file"),
  tar_target(streams_file, get_streams(watershed_file), format = "file"),
  
  # Stage 1 spatial harmonization: common CRS, grid, and extent
  tar_target(watershed_clipped, harmonize_watershed(watershed_file, config), format = "file"),
  tar_target(dem_harmonized, harmonize_dem(dem_file, watershed_file, config), format = "file"),
  tar_target(streams_clipped, harmonize_streams(streams_file, watershed_file, config), format = "file"),
  
  # Stage 1 attribute harmonization: apply the crosswalk
  tar_target(watershed_final,
             harmonize_attributes(watershed_clipped, crosswalk_file, "watershed_boundary"),
             format = "file"),
  tar_target(streams_final,
             harmonize_attributes(streams_clipped, crosswalk_file, "streams"),
             format = "file"),
  
  # Metadata
  tar_target(
    layer_catalog,
    build_layer_catalog(
      raw        = c(watershed_boundary = watershed_file,
                     dem = dem_file, streams = streams_file),
      harmonized = c(watershed_boundary = watershed_final,
                     dem = dem_harmonized, streams = streams_final)
    ),
    format = "file"
  ),
  tar_target(
    data_dictionary,
    build_data_dictionary(
      crosswalk_file,
      c(watershed_boundary = watershed_final,
        dem = dem_harmonized, streams = streams_final)
    ),
    format = "file"
  ),
  
  # Summary report: rebuilds whenever any layer or metadata file changes
  tar_quarto(report, "4_product/data_summary.qmd")
)