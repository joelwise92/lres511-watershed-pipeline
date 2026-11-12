# Decision log

Each entry records a processing decision, the alternatives considered, and the reason for the choice, numbered in the order the decisions were made. Entries marked DRAFT are placeholders to confirm or change.

## Entry template

### N. Short title
- **Decision:**
- **Alternatives considered:**
- **Reason:**
- **Affects:** files, layers, or pipeline steps

---

### 1. Project folder structure
- **Decision:** Use the 1_input / 2_protocol / 3_incremental / 4_product layout.
- **Alternatives considered:** Generic data/raw, data/interim, data/final layout.
- **Reason:** Matches the LRES 511 course convention and separates raw data, processing rules, intermediate outputs, and deliverables.
- **Affects:** Entire repository.

### 2. Pipeline runs from the project root
- **Decision:** Run the pipeline from the project root with targets::tar_make(). _targets.R sits at the root, and its cache is stored in 3_incremental/_targets via _targets.yaml.
- **Alternatives considered:** Running scripts from 2_protocol with ../ relative paths, as in class examples.
- **Reason:** targets expects to run from the project root; one working directory avoids path errors.
- **Affects:** All scripts in 2_protocol/R use paths relative to the project root.

### 3. Output coordinate reference system
- **Decision:** EPSG:5070 (NAD83 / CONUS Albers Equal Area).
- **Alternatives considered:** UTM zone for the pilot watershed; EPSG:4326 (geographic).
- **Reason:** Equal-area projection in meters that is valid across all Rocky Mountain watersheds, so the CRS does not change when the study area changes.
- **Affects:** All harmonized layers.

### 4. Target grid resolution
- **Decision:** 10 m, matching the 3DEP 1/3 arc-second DEM (entry 8).
- **Alternatives considered:** 1 m or 3 m (lidar); 30 m (the resolution of the LANDFIRE layers).
- **Reason:** The 10 m DEM is the finest elevation source in the pipeline, so a finer grid would add cells without adding detail. Coarser sources are resampled to it, and their real spatial detail is noted with each layer (soil polygons, entry 21; 800 m precipitation, entry 29; 30 m LANDFIRE, entries 40 and 41). At 10 m the pilot has about 1.06 million cells per layer, which runs quickly. Revisit if a lidar DEM is added (entry 8): a 1 m grid would have about 100 times as many cells.
- **Affects:** All raster layers; `resolution_m` in `study_area.yml`.

### 5. Pilot watershed
- **Decision:** Upper Tenderfoot Creek, HUC12 100301030801 (about 105.7 km², 26,100 acres).
- **Alternatives considered:** Fraser Experimental Forest (Colorado); other Rocky Mountain HUC12s with documented disturbance.
- **Reason:** Contains the Tenderfoot Creek Experimental Forest, a representative lodgepole pine watershed with documented shelterwood harvests and prescribed burns (1999–2003), untreated control sub-watersheds, and long-term research records. The HUC12 is about three times larger than the experimental forest itself.
- **Affects:** `study_area.yml`; all layers.

### 6. Watershed boundary version
- **Decision:** Use the WBD version that nhdplusTools returns by default (the 2025 WBD as of nhdplusTools 1.5.2). Record the WBD record load date (2024-08-15) in the retrieval log as the dataset version.
- **Alternatives considered:** Citing the 2020 WBD snapshot DOI; downloading the full WBD geodatabase.
- **Reason:** The load date comes from the data itself, so the log reflects what was actually downloaded rather than a fixed citation that may go out of date.
- **Affects:** `get_watershed.R`; retrieval log.

### 7. Raw layers saved in native form
- **Decision:** Save every raw layer to `1_input/` in its native coordinate system and values, with no reprojection, resampling, or attribute changes. All transformations happen later, in harmonization.
- **Alternatives considered:** Reprojecting during download.
- **Reason:** Keeps an unaltered copy of what each provider delivered, so every transformation is visible and repeatable in code.
- **Affects:** All acquisition scripts.

### 8. DEM source and extent
- **Decision:** USGS 3DEP 1/3 arc-second (~10 m) seamless DEM, current version, read directly from the USGS server and cropped to the watershed plus a 1 km buffer. Tile metadata (XML) saved to `1_input/source_metadata/dem/`.
- **Alternatives considered:** 1 m lidar DEM; downloading whole 1 x 1 degree tiles.
- **Reason:** 10 m keeps files small while the workflow is built and matches the draft grid resolution. Reading only the needed area avoids downloading full tiles. The buffer leaves room for future terrain calculations near the watershed edge. Lidar may be added later as a separate module.
- **Affects:** `get_dem.R`.

### 9. Stream network source
- **Decision:** NHDPlus HR network flowlines from the USGS web service, for flowlines intersecting the watershed. Non-network flowlines are excluded.
- **Alternatives considered:** NHDPlus V2 (medium resolution); downloading the full HU4 NHDPlus HR geodatabase.
- **Reason:** NHDPlus HR matches the detail of a 10 m DEM. The web service returns only the needed area. Network flowlines carry the routing and value-added attributes.
- **Affects:** `get_streams.R`.

### 10. DEM harmonization
- **Decision:** Reproject the DEM onto the common grid with bilinear resampling, mask to the watershed, and write as a cloud-optimized GeoTIFF with NoData = -9999. Grid edges are snapped to whole multiples of the cell size.
- **Alternatives considered:** Nearest-neighbor or cubic resampling; unsnapped grid extent.
- **Reason:** Bilinear suits continuous data like elevation. Snapping makes grids for different watersheds line up cell for cell.
- **Affects:** `harmonize_grid.R`; all future raster layers.

### 11. Stream clipping
- **Decision:** Clip flowlines to the watershed boundary. Attributes are not recalculated after clipping.
- **Alternatives considered:** Keeping whole flowlines; recalculating length and elevation for clipped segments.
- **Reason:** Keeps the product within the watershed. Note: attributes such as `length_km` and `elev_min_m` describe the full original flowline, so the outlet flowline's minimum elevation (1,617.5 m) is below the lowest DEM cell in the watershed (1,646.75 m).
- **Affects:** `harmonize_grid.R`; stream attributes.

### 12. Attribute crosswalk
- **Decision:** Keep 20 attributes (6 watershed, 13 streams, 1 DEM) and rename them to consistent snake_case names. Drop internal IDs, bookkeeping fields, extra routing fields, and modeled flow estimates (EROM `qama`, `vama`, and related fields).
- **Alternatives considered:** Keeping all source attributes; keeping modeled flow estimates.
- **Reason:** Keeps the product focused on attributes relevant to the research while documenting every dropped field in the crosswalk. Flow estimates can be restored by changing `keep` to TRUE.
- **Affects:** `crosswalk.csv`; `harmonize_attributes.R`; data dictionary.

### 13. Unit, date, and NoData conversions
- **Decision:** Convert NHDPlus smoothed elevations from centimeters to meters (multiply by 0.01). Convert `fdate` from milliseconds since 1970 to a date. Recode NHDPlus NoData (-9998) in slope and elevation fields to NA.
- **Alternatives considered:** Keeping source units.
- **Reason:** Stream elevations then match the DEM's units, and dates and missing values are consistent across layers. The -9998 code follows NHDPlus convention (TO CONFIRM in the NHDPlus HR user guide).
- **Affects:** `crosswalk.csv`; `harmonize_attributes.R`.

### 14. Feature code 55800
- **Decision:** Document feature code 55800 (artificial path through a waterbody) in the crosswalk description alongside the stream codes (46003, 46006, 46007).
- **Alternatives considered:** Removing artificial paths.
- **Reason:** The data dictionary showed feature codes up to 55800. Artificial paths keep the network connected through ponds and wetlands, so they are kept.
- **Affects:** `crosswalk.csv`; data dictionary.

### 15. Separate folders for intermediate and final outputs
- **Decision:** Reprojected and clipped vectors are written to `3_incremental/clipped/`; attribute-harmonized finals to `4_product/data/`. No pipeline step writes to a file another step produced.
- **Alternatives considered:** Writing intermediate and final vectors to the same folder.
- **Reason:** An earlier version wrote both to `4_product/data/` under the same file name, so the final step overwrote the clipped output. `targets` then saw the clipped file as changed and rebuilt it on every run. Separate folders fixed the loop.
- **Affects:** `harmonize_grid.R`; `harmonize_attributes.R`.

### 16. Soil data source
- **Decision:** SSURGO from the NRCS Soil Data Access service, via `soilDB`. Save the map unit polygons (whole, not clipped) and the component and horizon table unchanged; save the survey area name and version date as source metadata.
- **Alternatives considered:** STATSGO2 (coarser general soil map); gSSURGO raster download.
- **Reason:** A coverage check found SSURGO covers 100% of the watershed from a single survey, MT632 (Lewis and Clark National Forest Area), with no "not completed" map units, so the STATSGO2 fallback is not needed. The web service returns only the needed map units.
- **Affects:** `get_soils.R`.

### 17. Component K-factor from the first horizon with a value
- **Decision:** For each soil component, use the K-factor of the first horizon from the top that has one.
- **Alternatives considered:** The horizon starting at 0 cm; a depth-weighted average over a set depth.
- **Reason:** Most components begin with an organic (Oi) horizon, 0 to 7 cm thick, that has no K-factor, so a 0 cm rule would return mostly missing values. The first horizon with a value is the uppermost mineral horizon (usually A or E), the layer exposed to erosion once litter is disturbed. Components without an organic layer are handled by the same rule.
- **Affects:** `harmonize_soils.R`.

### 18. Keep both whole-soil and fine-earth K
- **Decision:** Produce separate layers for `kwfact` (whole soil, includes rock fragments) and `kffact` (fine earth only).
- **Alternatives considered:** Choosing one K-factor now.
- **Reason:** These soils are very stony, and in surface mineral horizons `kwfact` is often about half of `kffact` (for example, 0.20 vs. 0.37). The choice depends on the thesis analysis, so both are harmonized and the decision is left to the analysis stage, with input from my advisor.
- **Affects:** `harmonize_soils.R`; `soil_kw` and `soil_kf` layers.

### 19. Map unit K as a weighted average
- **Decision:** Map unit K is the average of component K values, weighted by component percent, using only components that have a K-factor.
- **Alternatives considered:** Dominant component only; weighted average including components without K as zero.
- **Reason:** Uses information from all soil components rather than only the largest one. Treating rock and rubble as zero would mix "no soil" with "low erodibility"; recording them separately (entry 20) keeps those meanings apart.
- **Affects:** `harmonize_soils.R`.

### 20. Percent of map unit without K
- **Decision:** Add a third soil layer recording the percent of each map unit made up of components with no K-factor.
- **Alternatives considered:** Not recording it.
- **Reason:** All components without K are rock outcrop, rubble land, pits, or water. Some map units are mostly rock (up to 65%), mainly on the canyon walls; without this layer they would look like ordinary soil with a low K. The gravel pit map unit (2486289) has no soil components, so its K values are NA and its percent without K is 100.
- **Affects:** `harmonize_soils.R`; `soil_pct_no_k` layer.

### 21. Rasterizing soil polygons
- **Decision:** Rasterize map unit values onto the common 10 m grid, assigning each cell the value of the polygon containing its center, then mask to the watershed with NoData = -9999.
- **Alternatives considered:** Keeping soils as polygons only; area-weighted values for cells crossing polygon edges.
- **Reason:** Puts soils on the same grid as the DEM for later analysis. Note: soil values are uniform within each map unit polygon, so the real spatial detail of the soil layers is the polygon, not the 10 m grid.
- **Affects:** `harmonize_soils.R`.

### 22. Map color schemes
- **Decision:** Use a separate palette for each kind of variable: terrain colors for elevation, yellow-orange-brown for K-factors, and grays for percent without K. Plot both K maps as separate figures on one shared color scale.
- **Alternatives considered:** The default palette for all maps, with each map scaled to its own range.
- **Reason:** With the default, the same colors meant different values on different maps; on separate scales, the two K maps looked nearly identical even though whole-soil K is much lower. A shared scale shows the real difference.
- **Affects:** `data_summary.qmd`.

### 23. Layers with more than one file
- **Decision:** Pass layers to the layer catalog and data dictionary as lists, so one layer can have several files. The catalog describes the first file of each layer and lists all of them.
- **Alternatives considered:** Separate catalog rows for each soil file.
- **Reason:** Soils produce two raw files (polygons and a horizon table) and three rasters plus a map unit table, but come from a single download.
- **Affects:** `metadata.R`; `_targets.R`.

### 24. Precipitation data source
- **Decision:** NOAA Atlas 14, Volume 12 (Interior Northwest: Idaho, Montana, Wyoming), Version 2, published September 2024.
- **Alternatives considered:** PRISM 30-year normals; NOAA Atlas 15 preliminary estimates; NOAA Atlas 2 (1973).
- **Reason:** Atlas 14 Volume 12 is the current authoritative precipitation frequency standard for Montana and replaces Atlas 2. It gives rainfall intensity for specific storms, which is more relevant to erosion than PRISM's average precipitation. Atlas 15 estimates are preliminary and under peer review, so they are not yet meant for use. Revisit this decision when Atlas 15 is published.
- **Affects:** `get_precip.R`; `study_area.yml`.

### 25. Storm set: series, return period, and durations
- **Decision:** Partial duration series; 2-year return period; durations of 30 minutes, 1 hour, and 6 hours; best estimates only, without the 90% confidence bounds. Set in `study_area.yml` (`precip` block).
- **Alternatives considered:** Annual maximum series; longer return periods (10- or 100-year); including confidence bounds.
- **Reason:** Frequent, intense storms do most erosion over time, and the partial duration series is NOAA's recommended series for frequent events. Three layers keep this stage manageable. Other return periods, durations, or bounds can be added by editing the config and crosswalk. TO CONFIRM with my advisor.
- **Affects:** `study_area.yml`; `get_precip.R`; `crosswalk.csv`.

### 26. Raw precipitation files kept as original zips
- **Decision:** Store the downloaded grid zips unchanged in `1_input/precip/` and read the ASCII grids directly from them. Save NOAA's point table at the watershed center as source metadata.
- **Alternatives considered:** Unzipping the grids into `1_input/`.
- **Reason:** Keeps the provider's files exactly as delivered. The point table records the Atlas version and gives NOAA's own values for checking the harmonized grids.
- **Affects:** `get_precip.R`; `harmonize_precip.R`; `metadata.R`.

### 27. Coordinate system for the precipitation grids
- **Decision:** Assign NAD83 geographic coordinates (EPSG:4269) when a grid file has no coordinate system defined.
- **Alternatives considered:** WGS84 geographic.
- **Reason:** The ASCII grids may not include a coordinate system; the layer catalog records "not defined in source file" when that is the case. NAD83 is the standard datum for NOAA Atlas 14. The difference from WGS84 is about 1 m, far smaller than the 800 m source cells. The match with NOAA's point values (entry 28) confirms the grids are placed correctly.
- **Affects:** `harmonize_precip.R`.

### 28. Converting depth to intensity
- **Decision:** Convert grid values from depth in thousandths of an inch to intensity in mm/hr by multiplying by 0.0254 and dividing by the duration in hours (factors 0.0508, 0.0254, and 0.004233 for 30 minutes, 1 hour, and 6 hours). `harmonize_precip()` reads the factors from the crosswalk, so they are recorded in one place.
- **Alternatives considered:** Keeping depth in the source units; computing the factors in code.
- **Reason:** Intensity in metric units matches the rest of the dataset. Validated against NOAA's point table at the watershed center: the grid gives 23.99, 14.33, and 4.60 mm/hr, and NOAA reports 24, 14, and 5 (rounded to whole numbers).
- **Affects:** `crosswalk.csv`; `harmonize_precip.R`.

### 29. Resampling precipitation to the common grid
- **Decision:** Crop each grid to the watershed plus a 2 km buffer, resample with bilinear interpolation from about 800 m to 10 m, and mask to the watershed with NoData = -9999.
- **Alternatives considered:** Nearest-neighbor resampling, which would keep the original 800 m blocks.
- **Reason:** Intensity is continuous, so bilinear is appropriate, and the buffer avoids missing cells at the watershed edge. Note: intensity varies only about 3% across the watershed, and the real spatial detail is the 800 m source cell, not the 10 m grid. Within this watershed, precipitation is nearly constant; differences will be larger between watersheds.
- **Affects:** `harmonize_precip.R`.

### 30. Automated precipitation checks
- **Decision:** Add three checks to the report: precipitation is on the same grid as the DEM; intensity at the watershed center is within 1 mm/hr of NOAA's point table; and shorter storms are more intense than longer ones in every cell.
- **Alternatives considered:** Checking by hand once.
- **Reason:** The checks rerun whenever the data or settings change, including for other watersheds or storm sets.
- **Affects:** `data_summary.qmd`.

### 31. Layer catalog reads zipped grids
- **Decision:** Let the layer catalog describe grids inside zip files in place, and record "not defined in source file" when a raw grid has no coordinate system.
- **Alternatives considered:** Unzipping the raw files.
- **Reason:** The catalog failed on the precipitation zips because it only recognized `.tif` rasters and vector files.
- **Affects:** `metadata.R`.

### 32. One-button run script
- **Decision:** Add `run.R` at the project root. The user sets the watershed's HUC12 on one line (or `"random"`) and clicks Source. `run.R` writes the HUC12 into `study_area.yml`, restores packages with `renv`, runs `tar_make()`, and opens the report.
- **Alternatives considered:** Editing the config and running `tar_make()` by hand.
- **Reason:** Reproducing the dataset for any watershed becomes a single step. The config remains the one file the pipeline reads, so the pipeline still tracks the study area.
- **Affects:** `run.R`; `study_area.yml`; README.

### 33. Testing approach
- **Decision:** Test the pipeline beyond the pilot in three ways: the two watersheds downstream of the pilot; hand-picked watersheds in other NOAA Atlas 14 regions (Colorado, Texas, Georgia); and random watersheds drawn by `run.R` (Montana, Arizona, Colorado, Nebraska, Virginia/West Virginia). Random tests are recorded automatically in `2_protocol/testing_log.csv`, which lists each watershed and its result.
- **Alternatives considered:** Testing the pilot only.
- **Reason:** Hand-picked watersheds tend to resemble the pilot; random ones find cases nobody thought to test. Issues found and their fixes are summarized in entry 36.
- **Affects:** `run.R`; `random_huc12.R`; `testing_log.csv`.

### 34. Retrieval log after testing
- **Decision:** After testing other watersheds, rebuild the pilot and trim the retrieval log to the newest row per layer, so the committed log describes the pilot's data only.
- **Alternatives considered:** Keeping every download; a separate log per watershed.
- **Reason:** Keeps the committed provenance record unambiguous. Test runs are documented in the testing log.
- **Affects:** `1_input/retrieval_log.csv`.

### 35. Automatic NOAA Atlas 14 volume lookup
- **Decision:** `get_precip()` asks NOAA's point service which Atlas 14 volume covers the watershed, then finds that volume's download folder in `2_protocol/atlas14_volumes.csv`. The config's `volume_prefix` is "auto" by default and can be overridden. Where Atlas 14 has no coverage (Oregon and Washington), the pipeline stops with a clear message.
- **Alternatives considered:** Setting the volume by hand; keying the table on project-area name.
- **Reason:** Removes a manual, region-specific setting. The table is keyed on volume number because two volumes share the name "Southwest." Folder codes were verified against NOAA's site. Intensities matched NOAA's published values in every volume tested (1, 8, 9, 11, and 12).
- **Affects:** `get_precip.R`; `atlas14_volumes.csv`; `study_area.yml`; crosswalk labels.

### 36. Issues found in testing, and fixes
- **Decision:** Fix the pipeline or its checks where testing showed they were tuned to the pilot or fragile; document data problems that can't be fixed.
- **Reason:** Testing outside the pilot found the following:

| Where | Issue | Resolution |
| --- | --- | --- |
| Colorado | Soil check failed on alpine rubble land and lakes, which correctly have no K-factor; K range check failed on a value of exactly 0.02 (stored-precision rounding) | Soil checks now separate missing soil data from rock and water (new INFO status); small tolerance on the K range |
| Texas, Georgia | Elevation check (500 to 4,500 m) was set for Rocky Mountain watersheds | Range changed to the lower 48 states (-100 to 4,500 m) |
| Montana, Colorado, Virginia/West Virginia | NHDPlus HR stream service outages and timeouts (502 and 504 errors, October 10, 2026); errors wrongly blamed the watershed | Service check before downloading; stream query split into tiles with paced retries; clear outage messages. The pilot gives identical results (135 flowlines) |
| Nebraska | NHDPlus HR stream elevations and slopes are placeholders (constant or zero values, minimum default slope), likely because its calculations fail in flat terrain | Flagged by the stream elevation check; documented. Zero is not treated as missing, since coastal streams can truly be at 0 m |
| Arizona | Watershed has no name in the Watershed Boundary Dataset | No change needed; the report shows the HUC12 code |

- **Affects:** `data_summary.qmd`; `get_streams.R`.

### 37. Stream order map
- **Decision:** Show stream order with a light-to-dark blue scale, line width increasing with order, and a legend.
- **Alternatives considered:** The default colors without a legend.
- **Reason:** The original map had no key, its colors did not run in any order, and it sat off-center.
- **Affects:** `data_summary.qmd`.

### 38. Updating R to 4.6.1
- **Decision:** After updating R, install the newest available package builds and snapshot them into `renv.lock`, which also records the new R version.
- **Alternatives considered:** Installing Rtools so `renv` can build the exact older versions from source.
- **Reason:** `renv` keeps a separate library for each R version. The lockfile's older versions had no ready-made Windows builds for R 4.6 and failed to compile without Rtools. The README states the project's R version and notes that on Windows, Rtools lets `renv` restore exact versions across R updates.
- **Affects:** `renv.lock`; README.

### 39. Stream source and stream elevations
- **Decision:** Keep querying the NHDPlus HR map service (in tiles with paced retries, entry 36), and keep the NHDPlus elevation attributes for streams.
- **Alternatives considered:** Downloading NHDPlus HR files by region, which is more reliable but means much larger downloads; taking stream elevations from the DEM, which would avoid placeholder values like those found in Nebraska.
- **Reason:** My judgment, without instructor input: the map service works for the pilot and returns only the needed area, and the pilot's stream elevations pass the stream elevation check. Revisit the service if outages continue, and the elevations before using the pipeline in flat terrain.
- **Affects:** `get_streams.R`; `crosswalk.csv`; stream attributes.

### 40. Forest structure source
- **Decision:** LANDFIRE 2024 canopy cover (`LF2024_CC`) and canopy height (`LF2024_CH`) from the LANDFIRE Product Service, requested in EPSG:5070 for the watershed plus a 1 km buffer. Canopy height is converted from decimeters to meters. Both are resampled from 30 m to the 10 m grid with nearest neighbor.
- **Alternatives considered:** Bilinear resampling; other LANDFIRE fuel or vegetation products. DRAFT: confirm the alternatives actually weighed.
- **Reason:** LANDFIRE stores both products as classes (cover 0, 15, 25, ... 75%; height in class steps), so bilinear would invent values between classes. Requesting the output CRS from LANDFIRE avoids a second reprojection. The report checks that each layer still has 20 or fewer distinct values.
- **Affects:** `get_forest.R`; `harmonize_forest.R`; `crosswalk.csv`.

### 41. Disturbance history source and summary layers
- **Decision:** LANDFIRE Annual Disturbance (final products), 1999 to 2025, requested in batches for the watershed plus a 1 km buffer. Each year's codes are translated with that year's own LANDFIRE attribute table, because code meanings change between years. Product names come from `2_protocol/landfire_dist_products.csv`, verified against LANDFIRE's product table. The annual layers are summarized per cell into five layers: last harvest year, last fire year, last insect year, number of disturbed years, and severity of the most recent disturbance.
- **Alternatives considered:** Assembling disturbance directly from agency sources (MTBS burn severity, USFS Aerial Detection Survey, FACTS activities).
- **Reason:** LANDFIRE was more consistent to retrieve: one programmatic service (`rlandfire`) delivers every year in the same format on the same 30 m grid, instead of three agency sources with different access methods, formats, and vocabularies. Note: LANDFIRE may under-record insect mortality, which develops gradually over several years.
- **Affects:** `get_disturbance.R`; `harmonize_disturbance.R`; `landfire_dist_products.csv`.

### 42. Disturbance type groups
- **Decision:** Map each LANDFIRE disturbance type to harvest, fire, insect, or other in `2_protocol/dist_type_groups.csv`. Prescribed fire is grouped with wildfire. "Unknown/Possibly Fire" stays in other, so the fire group counts only attributed fire. Mastication and the mechanical types are in other. Types missing from the file are treated as other with a warning, and the report checks that every type found is listed.
- **Alternatives considered:** A separate prescribed-fire group; grouping mechanical treatments with harvest.
- **Reason:** Keeps the groups tied to LANDFIRE's own labels, which are recorded with each assignment in the code lookup file (entry 44). DRAFT: confirm the mechanical types against LANDFIRE's definitions, since newer years appear to use "Mechanical Add/Remove/Unknown" where older years use harvest and thinning types.
- **Affects:** `dist_type_groups.csv`; `harmonize_disturbance.R`; `data_summary.qmd`.

### 43. Disturbance severity classes
- **Decision:** Rank LANDFIRE severity labels by their first word: Low or Unburned = 1, Medium or Moderate = 2, High = 3. Any other label (No Severity, Increased Green, blank) = 0, meaning disturbed but without a severity class. `dist_last_severity` is the class of the most recent disturbance of any group.
- **Alternatives considered:** Leaving unranked labels as missing.
- **Reason:** The first version recognized Medium but not Moderate, which newer LANDFIRE years use, and left unranked labels missing. Because the summary keeps the newest non-missing value, an older severity showed through wherever the most recent disturbance was moderate or unclassed. Found on October 21, 2026, by reviewing the code lookup file. Code 0 makes the layer describe the most recent disturbance in every disturbed cell.
- **Affects:** `harmonize_disturbance.R`; `build_eml.R` (code list); `crosswalk.csv`; `data_summary.qmd`.

### 44. Disturbance code lookup file
- **Decision:** Write `4_product/data/disturbance_codes_<HUC12>.csv`, listing every LANDFIRE value, disturbance type, and severity label used, by year, with the group and severity class assigned to each and whether the type was in the groups file.
- **Alternatives considered:** Documenting the groups only in the protocol file.
- **Reason:** Agencies use disturbance terms differently, so the product carries LANDFIRE's own labels rather than paraphrases. The file also exposed the severity problem in entry 43.
- **Affects:** `harmonize_disturbance.R`; `_targets.R`; `data_summary.qmd`.

### 45. Metadata additions (after Michener, Creating and Managing Metadata)
- **Decision:** Add the following:
  - MD5 checksums for every raw download in the retrieval log.
  - The scripts and code version that made each layer, in the layer catalog.
  - Source dates and vertical datum for the DEM tiles.
  - Missing-value codes and the severity code list in the EML.
  - A changelog (`2_protocol/changelog.csv`) that sets the EML revision number and change history.
- **Alternatives considered:** Keeping provenance implied by the folder structure; checksums on final files only.
- **Reason:** Provider portals update without notice, so checksums show whether a raw file has changed. Recording code and revisions makes each product traceable to how it was made. Notes for maintenance: the changelog accepts dates as YYYY-MM-DD or M/D/YYYY (Excel rewrites them), and processing notes must not contain angle brackets, which EML reads as XML tags.
- **Affects:** `utils.R`; `metadata.R`; `get_dem.R`; `build_eml.R`; `_targets.R`; `changelog.csv`.

### 46. DEM source dates
- **Decision:** Record the source date range and vertical datum (NAVD88) of each 3DEP tile. The tiles covering the pilot span source dates from 1952 to 2022.
- **Alternatives considered:** None yet. DRAFT: the 1 m lidar DEM or USGS lidar project boundaries (WESM) would give dates for each area.
- **Reason:** The seamless DEM is a mosaic of source projects from different years, so the tile date range does not say when a given cell was surveyed. Before using the DEM as pre- or post-disturbance terrain, find which source covers the watershed.
- **Affects:** `get_dem.R`; layer catalog.

### 47. Checksums for earlier downloads
- **Decision:** Layers downloaded before October 21, 2026 (streams, precipitation, forest, disturbance) are marked "not recorded" for checksums rather than hashed now.
- **Alternatives considered:** Hashing the existing files; re-downloading every layer.
- **Reason:** Hashing a file now would record a check that never happened at download time. Re-downloading would add checksums but could also bring in newer provider versions. These layers get checksums the next time they are downloaded.
- **Affects:** `1_input/retrieval_log.csv`; layer catalog.

### 48. Soil Data Access maintenance window
- **Decision:** `get_soils()` checks every Soil Data Access response and stops with a clear outage message when the service returns something other than a table.
- **Alternatives considered:** Leaving the original check, which failed with "missing value where TRUE/FALSE needed."
- **Reason:** NRCS takes Soil Data Access down for daily maintenance from 12:30 to 12:45 AM Central. A run during that window failed with a cryptic error that pointed at the code, not the service. Like the NHDPlus outages in entry 36, the error should name the service so the fix (wait and rerun) is obvious.
- **Affects:** `get_soils.R`.

### 49. Repository contents and hosting
- **Decision:** Host the repository on GitHub. Commit code, protocol files, documentation, the products in `4_product/`, the retrieval log, and the source metadata archive. Do not commit raw data in `1_input/` or anything in `3_incremental/`. Code is under the MIT License (`LICENSE`); data products are under CC BY 4.0.
- **Alternatives considered:** Leaving all of `1_input/` out of git, as the project plan first described.
- **Reason:** The pipeline downloads raw data again, so committing it would only add large files. The retrieval log and source metadata archive are small, are part of the planned metadata products, and can't be recreated: a later run gets new retrieval dates and possibly new provider versions.
- **Affects:** `.gitignore`; `LICENSE`; README.

### 50. Road source
- **Decision:** USFS National Forest System roads from the Forest Service Enterprise Data Warehouse map service (`EDW_RoadBasic_01`, layer 0), queried for the watershed's bounding box in pages of 2,000 and kept where segments touch the watershed. Saved unchanged in NAD83 geographic coordinates, then reprojected and clipped like streams. Kept attributes: road number, name, GIS length (converted from miles to km), jurisdiction, route status, operational and objective maintenance levels, functional class, surface type, and vehicles the road is open to.
- **Alternatives considered:** TIGER/Line roads; OpenStreetMap (the two other sources named in the project plan).
- **Reason:** DRAFT: confirm. Forest roads are the roads most relevant to sediment delivery on national forest land, and the USFS layer carries their maintenance level and surface type, which TIGER and OpenStreetMap lack or record inconsistently. The limitation is coverage: county, state, and private roads are not included, and a watershed outside national forest land gets an empty roads layer. EDW updates daily, so the retrieval date is the effective version.
- **Affects:** `get_roads.R`; `harmonize_grid.R`; `crosswalk.csv`; `_targets.R`; `metadata.R`; `data_summary.qmd`.

### 51. USFS TreeMap
- **Decision:** TreeMap, listed in the project plan for forest structure, was not attempted. LANDFIRE canopy cover and height (entry 40) provide forest structure for this project.
- **Alternatives considered:** Adding TreeMap alongside LANDFIRE.
- **Reason:** DRAFT: add whether TreeMap is still planned for the thesis.
- **Affects:** Project scope.