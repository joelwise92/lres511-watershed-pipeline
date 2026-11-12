# Pipeline definition. Run with targets::tar_make() from the project root.
library(targets)
library(tarchetypes)

tar_option_set(packages = c("sf", "yaml", "nhdplusTools", "terra", "soilDB", "EML", "rlandfire"))

# Load every function in 2_protocol/R
tar_source("2_protocol/R")

list(
  # Config and protocol files are tracked, so editing any reruns what depends on it
  tar_target(config_file, "2_protocol/config/study_area.yml", format = "file"),
  tar_target(config, read_config(config_file)),
  tar_target(crosswalk_file, "2_protocol/crosswalk.csv", format = "file"),
  tar_target(dist_groups_file, "2_protocol/dist_type_groups.csv", format = "file"),
  tar_target(dist_products_file, "2_protocol/landfire_dist_products.csv", format = "file"),
  
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
  
  # Stage 2 soils: SSURGO K-factor
  tar_target(soils_files, get_soils(watershed_file), format = "file"),
  tar_target(soils_harmonized, harmonize_soils(soils_files, watershed_file, config),
             format = "file"),
  
  # Stage 2 precipitation: NOAA Atlas 14 rainfall intensity
  tar_target(atlas14_file, "2_protocol/atlas14_volumes.csv", format = "file"),
  tar_target(precip_files, get_precip(watershed_file, config, atlas14_file), format = "file"),
  tar_target(precip_harmonized,
             harmonize_precip(precip_files, watershed_file, crosswalk_file, config),
             format = "file"),
  
  # Stage 3 (test): LANDFIRE forest structure
  tar_target(forest_files, get_forest(watershed_file, config), format = "file"),
  tar_target(forest_harmonized,
             harmonize_forest(forest_files, watershed_file, crosswalk_file, config),
             format = "file"),
  
  # Stage 3 (test): LANDFIRE annual disturbance history
  tar_target(dist_files, get_disturbance(watershed_file, config, dist_products_file),
             format = "file"),
  tar_target(dist_harmonized,
             harmonize_disturbance(dist_files, watershed_file, dist_groups_file,
                                   dist_products_file, config),
             format = "file"),
  
  # Metadata
  tar_target(
    layer_catalog,
    build_layer_catalog(
      raw        = list(watershed_boundary = watershed_file, dem = dem_file,
                        streams = streams_file, soils = soils_files,
                        precip = precip_files, forest = forest_files,
                        disturbance = dist_files),
      harmonized = list(watershed_boundary = watershed_final, dem = dem_harmonized,
                        streams = streams_final, soils = soils_harmonized[1:3],
                        precip = precip_harmonized, forest = forest_harmonized,
                        disturbance = dist_harmonized)
    ),
    format = "file"
  ),
  tar_target(
    data_dictionary,
    build_data_dictionary(
      crosswalk_file,
      list(watershed_boundary = watershed_final, dem = dem_harmonized,
           streams = streams_final, soil_kw = soils_harmonized[1],
           soil_kf = soils_harmonized[2], soil_pct_no_k = soils_harmonized[3],
           precip_2yr_30m = precip_harmonized[1],
           precip_2yr_60m = precip_harmonized[2],
           precip_2yr_06h = precip_harmonized[3],
           forest_cc = forest_harmonized[1], forest_ch = forest_harmonized[2],
           dist_last_harvest_year = dist_harmonized[1],
           dist_last_fire_year    = dist_harmonized[2],
           dist_last_insect_year  = dist_harmonized[3],
           dist_count             = dist_harmonized[4],
           dist_last_severity     = dist_harmonized[5])
    ),
    format = "file"
  ),
  
  # Standards-based metadata (EML)
  tar_target(eml_settings_file, "2_protocol/eml_settings.yml", format = "file"),
  tar_target(changelog_file, "2_protocol/changelog.csv", format = "file"),
  tar_target(
    eml_file,
    build_eml(
      data_dictionary, layer_catalog, eml_settings_file, watershed_final,
      files = list(watershed_boundary = watershed_final, streams = streams_final,
                   dem = dem_harmonized,
                   soil_kw = soils_harmonized[1], soil_kf = soils_harmonized[2],
                   soil_pct_no_k = soils_harmonized[3],
                   precip_2yr_30m = precip_harmonized[1],
                   precip_2yr_60m = precip_harmonized[2],
                   precip_2yr_06h = precip_harmonized[3],
                   forest_cc = forest_harmonized[1], forest_ch = forest_harmonized[2],
                   dist_last_harvest_year = dist_harmonized[1],
                   dist_last_fire_year    = dist_harmonized[2],
                   dist_last_insect_year  = dist_harmonized[3],
                   dist_count             = dist_harmonized[4],
                   dist_last_severity     = dist_harmonized[5]),
      config = config,
      changelog_file = changelog_file
    ),
    format = "file"
  ),
  
  # Summary report: rebuilds whenever any layer or metadata file changes
  tar_quarto(report, "4_product/data_summary.qmd")
)