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
- **Decision:** 10 m.
- **Alternatives considered:** 1 m or 3 m (lidar); 30 m (Landsat-based layers).
- **Reason:** Placeholder until pilot watershed size and lidar file sizes are known.
- **Affects:** All raster layers.

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