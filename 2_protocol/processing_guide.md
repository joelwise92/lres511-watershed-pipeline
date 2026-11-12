# Processing guide

This guide explains how the pipeline works, how to run it for a new watershed, how to change its settings or add a layer, and how to fix common problems. For why each decision was made, see `decision_log.md`.

## 1. How the pipeline works

The pipeline is defined in `_targets.R` and run by the `targets` package. Each step (a "target") is a function in `2_protocol/R/` that reads files and writes files. `targets` tracks every step's inputs, so when something changes, only the affected steps rerun. Run `targets::tar_visnetwork()` to see the full diagram.

Data moves through four stages:

| Stage | What happens | Where files go |
| --- | --- | --- |
| 1. Acquisition | Each source is downloaded by script and saved unchanged, with the provider's metadata and a retrieval log entry | `1_input/` |
| 2. Spatial harmonization | Layers are reprojected to one CRS, resampled to one grid, and clipped or masked to the watershed | `3_incremental/` (intermediate), `4_product/data/` (rasters) |
| 3. Attribute harmonization | Vector attributes are renamed, converted to consistent units, and cleaned of NoData codes, following `crosswalk.csv` | `4_product/data/` |
| 4. Documentation | The layer catalog, data dictionary, EML metadata, and report are built from the data and logs | `4_product/` |

Two rules keep the pipeline reliable:

- **Raw files are never edited.** Everything in `1_input/` is exactly what the provider delivered. All changes happen in later stages, in code.
- **No step writes a file another step produced.** Intermediate and final files go to different folders. (An early version broke this rule and rebuilt endlessly; see the decision log.)

## 2. Running the pipeline

1. Open `project.Rproj` in RStudio. This sets the working directory to the project root, which every path depends on.
2. In `run.R`, set `huc12 <- "..."` to a 12-digit HUC12 code, or `"random"`.
3. Click **Source**.

`run.R` writes the HUC12 into `study_area.yml`, restores packages with `renv::restore()`, runs `targets::tar_make()`, and opens the report. If a step fails, it prints the error and stops; finished steps are kept, so running again resumes from the failure.

Useful Console commands:

| Command | Purpose |
| --- | --- |
| `targets::tar_make()` | Run the pipeline (what `run.R` calls) |
| `targets::tar_visnetwork()` | Diagram of all steps and their status |
| `targets::tar_outdated()` | Which steps would rerun |
| `targets::tar_read(name)` | The output of a step, e.g. `tar_read(dem_harmonized)` |
| `targets::tar_meta(fields = error, complete_only = TRUE)` | Error messages from failed steps |
| `targets::tar_invalidate(name)` | Force one step (and everything after it) to rerun |

**Switching watersheds** rebuilds every step, because the config changed. Raw stream downloads are reused if that watershed's file already exists in `1_input/streams/`; other layers are downloaded again.

## 3. Configuration

### `2_protocol/config/study_area.yml`

| Setting | Meaning |
| --- | --- |
| `study_area: huc12` | The watershed (set by `run.R`) |
| `crs` | EPSG code for all outputs (5070, NAD83 / CONUS Albers, in meters) |
| `resolution_m` | Grid cell size (10 m) |
| `precip: volume_prefix` | `"auto"` looks up the NOAA Atlas 14 volume; or a folder code such as `"inw"` |
| `precip: ari_years` | Storm return period in years (2) |
| `precip: durations` | Storm durations, e.g. `["30m", "60m", "06h"]` |

Changing `crs` or `resolution_m` regrids every layer. Changing the storm settings also requires matching crosswalk rows (section 5).

### `2_protocol/eml_settings.yml`

Title, abstract, creator, keywords, license, and methods overview for the EML metadata. The pipeline refuses to build EML while the creator fields still contain placeholders.

## 4. The layers

| Layer | Function | Source and method | Key decisions |
| --- | --- | --- | --- |
| Watershed boundary | `get_watershed()` | WBD via `nhdplusTools::get_huc()` | WBD load date logged as version |
| DEM | `get_dem()`, `harmonize_dem()` | 3DEP 1/3 arc-second tiles read directly from USGS, cropped to watershed + 1 km | Bilinear resampling; grid snapped to multiples of the cell size; masked to watershed |
| Streams | `get_streams()`, `harmonize_streams()` | NHDPlus HR network flowlines, queried in a 2 x 2 tile grid with paced retries | Clipped to watershed; attributes describe whole flowlines, not clipped pieces |
| Soils | `get_soils()`, `harmonize_soils()` | SSURGO map units, components, and horizons via `soilDB` | Component K from the first horizon with a value (skips organic layers); map unit K is a component-percent weighted mean; both kwfact and kffact kept; percent of map unit without K recorded |
| Rainfall intensity | `get_precip()`, `harmonize_precip()` | NOAA Atlas 14 grids; volume found automatically from NOAA's point service | Depth (0.001 in) converted to mm/hr using crosswalk factors; bilinear resampling from ~800 m |

## 5. Protocol files

### `crosswalk.csv`

Maps each source attribute to its harmonized name, units, and conversions. Columns:

| Column | Meaning |
| --- | --- |
| `layer`, `source_attribute` | Which layer and source field |
| `keep` | TRUE to include in the final data; FALSE rows document what was dropped |
| `harmonized_name`, `units`, `description` | The final name, units, and definition (these feed the data dictionary and EML) |
| `source_units`, `multiply_by` | Unit conversion, e.g. 0.01 for centimeters to meters |
| `nodata_source` | Source NoData code to convert to NA, e.g. -9998 |

To keep a dropped attribute, set `keep` to TRUE and fill in its name, units, and description. Edit the crosswalk in RStudio or with R, not Excel, which can reformat values.

### `atlas14_volumes.csv`

Maps NOAA Atlas 14 volume numbers to download folders. To support a new volume, confirm its folder on NOAA's site holds files named like `<folder>2yr30ma.zip`, then add a row.

### `decision_log.md`

Add a numbered entry for every processing decision: the decision, alternatives considered, the reason, and what it affects.

## 6. Quality checks

The report's quality checks run every time the data changes. Each row is marked:

- **PASS**: the check passed.
- **CHECK**: something is unexpected. Not always an error; look at the Result column and the decision log.
- **INFO**: describes the watershed rather than testing the data (for example, the share that is rock or water).

Checks cover: one CRS for all layers; grid size and alignment; soil and rainfall rasters on the DEM's grid; no missing DEM or soil data inside the watershed; elevations within the lower 48 range; streams inside the watershed and consistent with DEM elevations; K-factors in SSURGO's range; K missing only in map units with no soil; rainfall at the watershed center within 1 mm/hr of NOAA's published value; and shorter storms more intense than longer ones.

## 7. Adding a layer

1. Write `get_<layer>()` in `2_protocol/R/`: download to `1_input/<layer>/` unchanged, save the provider's metadata to `1_input/source_metadata/<layer>/`, call `log_retrieval()`, and return the file path(s).
2. Write the harmonization function: reproject with `read_watershed()` and `make_template()` (in `harmonize_grid.R`), write rasters to `4_product/data/` and vectors via `3_incremental/` and `harmonize_attributes()`.
3. Add crosswalk rows for its variables.
4. Add both targets to `_targets.R`, and add the layer to the `layer_catalog`, `data_dictionary`, and `eml_file` targets.
5. Add a processing note for it in `processing_notes` in `metadata.R`.
6. Add maps and checks to `data_summary.qmd`.
7. Run, check the report, add decision log entries, and commit.

## 8. Troubleshooting

| Problem | Cause and fix |
| --- | --- |
| `cannot open file '2_protocol/R/...': No such file or directory` | R is in the wrong folder. Open the project with `project.Rproj`, or run `setwd()` to the folder containing `_targets.R`. |
| `there is no package called '...'` or "project is out-of-sync" | Run `renv::restore()`. If you installed something new, run `renv::snapshot()` to record it. |
| Package installs fail with `'make' not found` after updating R | The lockfile's older package versions need compiling for the new R. Either accept the latest versions when `renv` offers them and run `renv::snapshot()`, or install Rtools (Windows) and restore again. |
| `NHDPlus HR web service is not responding` | USGS stream service outage. Wait and rerun; finished steps are kept. Check `https://hydro.nationalmap.gov/arcgis/rest/services/NHDPlus_HR/MapServer` in a browser. |
| `NHDPlus HR did not return flowlines for ... tiles` or `Request failed [504]` | The service is timing out (it reports timeouts the same way as an area with no streams). Test with the pilot: if `nhdplusTools::get_nhdphr()` fails there too, the service is struggling; wait and rerun. |
| `NOAA Atlas 14 has no coverage` | The watershed is in Oregon or Washington. Not supported until NOAA Atlas 15 is published. |
| `Atlas 14 Volume N is not in atlas14_volumes.csv` | Add that volume's folder (section 5). |
| `No retrieval log entry for ...` | A raw file exists without a log entry. Delete the file and rerun to download and log it again. |
| Stream elevation check says CHECK, with constant or zero stream elevations | NHDPlus HR has placeholder elevations in some flat areas. The data is unusable there; use the DEM for elevation. |
| A step reruns every time with no changes | A step is overwriting another step's output file. Check `targets::tar_read()` paths for two steps writing the same file. |
| Pasted commands are ignored, or `Unrecognized response` | R was waiting for an answer to a `[Y/n]` prompt or menu. Answer it first, then paste the next command. |
| `Permission denied` or "file in use" errors | A sync service (such as OneDrive) is locking files. Pause syncing or move the project to a non-synced folder. |
| A downloaded layer needs refreshing (e.g. a provider published an update) | Delete its raw file in `1_input/` and rerun. Stream files are reused until deleted. |