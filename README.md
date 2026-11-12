# Reproducible aggregation of public geospatial data for steep-terrain watersheds

An R pipeline that builds a harmonized, documented geospatial dataset for any watershed in the lower 48 states from public sources: terrain, streams, soil erodibility, and rainfall intensity. One command downloads every layer, puts them on a common grid with consistent attributes and units, documents every step, runs quality checks, and produces a summary report and standards-based (EML) metadata.

The pilot watershed is **Upper Tenderfoot Creek, Montana (HUC12 100301030801)**, which contains the Tenderfoot Creek Experimental Forest. The project is an LRES 511 (Environmental Data Management) term project supporting thesis research on erosion and sediment delivery in steep, disturbed Rocky Mountain watersheds.

Author: Joel Wise, Montana State University

## Quick start

**Requirements:** R 4.6.1 and RStudio. Quarto comes with RStudio. Git is optional. On Windows, installing [Rtools](https://cran.r-project.org/bin/windows/Rtools/) lets `renv` install exact package versions even after an R update (see the processing guide).

1. Download or clone this repository.
2. Open `project.Rproj` in RStudio. Always open the project this way, so R starts in the right folder.
3. Open `run.R` and set the watershed's 12-digit HUC12 code on the `huc12 <-` line (keep the quotes).
4. Click **Source** (top right of the editor).

`run.R` installs the exact package versions recorded in `renv.lock`, builds everything, and opens the report. A first run takes a few minutes; later runs skip anything that hasn't changed.

To find a watershed's HUC12 code from a point on a map:

```r
source("2_protocol/R/utils.R")
source("2_protocol/R/get_watershed.R")
find_huc12(lon = -110.93, lat = 46.93)   # longitude first; negative in the US
```

To test the pipeline on a random watershed, set `huc12 <- "random"` in `run.R`. Random tests are recorded in `2_protocol/testing_log.csv`.

## What it produces

All in `4_product/`:

| File | Contents |
| --- | --- |
| `data/` | Harmonized layers: watershed boundary and streams (GeoPackage); DEM, soil K-factors, percent non-soil, and rainfall intensity (cloud-optimized GeoTIFF). All in EPSG:5070 on a 10 m grid. |
| `data_summary.html` | Report with maps, automated quality checks, the layer catalog, and the data dictionary |
| `data_dictionary.csv` | Every variable: definition, units, data type, range, missing values, processing |
| `layer_catalog.csv` | Every layer: source, version, retrieval date, native and output coordinate systems, processing |
| `eml.xml` | Ecological Metadata Language 2.2 metadata, validated against the schema |

The outputs included in this repository are for the pilot watershed. Running another watershed replaces them on your computer.

## Data sources

| Layer | Source | Access |
| --- | --- | --- |
| Watershed boundary | USGS Watershed Boundary Dataset | `nhdplusTools` |
| Elevation | USGS 3DEP 1/3 arc-second (~10 m) DEM | Direct read of 3DEP tiles |
| Streams | USGS NHDPlus High Resolution network flowlines | `nhdplusTools` web service query |
| Soils | NRCS SSURGO (K-factors) | `soilDB` Soil Data Access |
| Rainfall intensity | NOAA Atlas 14, 2-year storm (30 min, 1 hr, 6 hr) | NOAA grid downloads |

## Coverage and limits

- Works anywhere in the lower 48 states except **Oregon and Washington**, which have no NOAA Atlas 14 coverage. Tested to completion in Montana, Colorado, Texas, Georgia, Arizona, and Nebraska; some tests stopped at the stream download during USGS service outages (see `2_protocol/testing_log.csv` and the decision log).
- The NHDPlus HR stream service is sometimes slow or unavailable. The pipeline retries and reports outages clearly; rerun later and it picks up where it stopped.
- Soil and rainfall values are on a 10 m grid, but their real spatial detail is the soil map unit polygon and the ~800 m NOAA grid cell.

## Project structure

```
project/
├── run.R                       # one-button run: set the watershed, click Source
├── README.md
├── project.Rproj
├── _targets.R                  # pipeline definition
├── _targets.yaml               # stores the targets cache in 3_incremental/
├── renv.lock, renv/, .Rprofile # package versions (renv)
├── 1_input/                    # raw downloads, unchanged (rebuilt; not in git)
│   ├── retrieval_log.csv       # every download: source, version, date (in git)
│   └── source_metadata/        # providers' original metadata (in git)
├── 2_protocol/                 # everything that defines the processing
│   ├── config/study_area.yml   # watershed, CRS, resolution, storm settings
│   ├── R/                      # pipeline functions
│   ├── crosswalk.csv           # source attributes -> harmonized names, units, conversions
│   ├── atlas14_volumes.csv     # NOAA Atlas 14 volume -> download folder
│   ├── eml_settings.yml        # title, abstract, creator, license for the EML
│   ├── decision_log.md         # every processing decision and why
│   ├── processing_guide.md     # how the pipeline works and how to adapt it
│   └── testing_log.csv         # random-watershed test results
├── 3_incremental/              # intermediate files and targets cache (rebuilt; not in git)
└── 4_product/                  # final data, report, dictionary, catalog, EML
```

## Documentation

- **`2_protocol/processing_guide.md`**: how each stage works, how to change settings or add a layer, and troubleshooting
- **`2_protocol/decision_log.md`**: every processing decision, the alternatives, and the reasons
- **`4_product/data_summary.html`**: the report, including quality checks

## License

Data products are released under the Creative Commons Attribution 4.0 International License (CC BY 4.0). Source data are public domain products of USGS, NRCS, and NOAA.