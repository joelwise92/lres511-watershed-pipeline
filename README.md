# Reproducible aggregation of public geospatial data for steep-terrain watersheds

An R pipeline that downloads public terrain, hydrography, soil, precipitation, forest, and disturbance data for a watershed, harmonizes them onto a common grid with consistent metadata, and documents every processing step. LRES 511 term project.

## Folder structure

- `1_input/`: raw data exactly as downloaded, plus the retrieval log (rebuilt by the pipeline; not committed except the log)
- `2_protocol/`: config file, R functions, metadata crosswalk, decision log, processing guide
- `3_incremental/`: intermediate outputs and the targets cache (rebuilt by the pipeline; not committed)
- `4_product/`: final harmonized dataset and documentation

## Running the pipeline

1. Open the project in RStudio (the project root is the working directory).
2. Restore packages: `renv::restore()`
3. Set the study area in `2_protocol/config/study_area.yml`.
4. Run: `targets::tar_make()`
5. View the pipeline: `targets::tar_visnetwork()`

## Changing the study area

Edit `huc12` in `2_protocol/config/study_area.yml` and rerun `targets::tar_make()`.
