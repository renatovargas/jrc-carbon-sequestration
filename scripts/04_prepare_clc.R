# Reduce the Corine Land Cover accounting layers to 1 km shares of the land categories of the inventory.
#
# Why    : the 100 m layers weigh about 0.9 GB, and the accounts need only the share of each 1 km cell.
# Inputs : refs/clc_accounting/CLC<year>ACC_V2024_21.tif
#          CORINE Land Cover accounting layers, version 21, 100 m, EPSG:3035, for 2000, 2006, 2012, 2018 and 2024
#          (European Environment Agency, doi:10.2909/a65428d3-bd66-4b47-bcf9-6bfd6fa5df0c for 2024).
#          The raster values are the CLC codes (111 to 523).
#          data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0123_INCA.gpkg (NUTS 2024 boundaries)
# Outputs: data/inputs/corine/CLC<year>_forest_pct_1km.tif
#            Percentage (whole numbers, 0 to 100) of each 1 km cell covered by forest (CLC 311, 312, 313 and 324).
#            Each cell holds 100 cells of 100 m, so whole percentages are exact. Read with read_forest_share().
#          data/inputs/corine/clc_ecosystem_area_by_nuts.rds
#            Hectares of each land type by NUTS region (levels 0, 2 and 3) and year.
#          refs/clc_1km_cache/CLCACC<year>_land_types_1km.tif, the shares of all land types, not versioned.
# Types  : Land types follow the land use categories of the inventory (CRF 4A to 4F). Water bodies (511 to 523)
#          belong to no land type.
# Run    : source("scripts/04_prepare_clc.R", encoding = "UTF-8"), from the project root. Needs the files in
#          refs/. Resumable, because years whose outputs already exist are skipped.

source("scripts/helpers_common.R", encoding = "UTF-8")
library(sf)

clc_dir <- "refs/clc_accounting"
out_dir <- "data/inputs/corine"
cache_dir <- "refs/clc_1km_cache"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(cache_dir, showWarnings = FALSE, recursive = TRUE)

years <- c(2000, 2006, 2012, 2018, 2024)

land_types <- list(
  forest = c(311, 312, 313, 324),
  cropland = c(211, 212, 213, 221, 222, 223, 241, 242, 243, 244),
  grassland = c(231, 321),
  wetlands = c(411, 412),
  settlements = c(111, 112, 121, 122, 123, 124, 131, 132, 133, 141, 142),
  other_land = c(322, 323, 331, 332, 333, 334, 335, 421, 422, 423)
)

template <- grid_1km()
agg_factor <- 10

for (year in years) {
  forest_file <- file.path(out_dir, sprintf("CLC%s_forest_pct_1km.tif", year))
  cache_file <- file.path(cache_dir, sprintf("CLCACC%s_land_types_1km.tif", year))

  if (!file.exists(cache_file)) {
    clc <- crop(rast(file.path(clc_dir, sprintf("CLC%sACC_V2024_21.tif", year))), template)
    levels(clc) <- NULL
    coltab(clc) <- NULL

    shares <- lapply(land_types, \(codes) aggregate(clc %in% codes, fact = agg_factor, fun = "mean", na.rm = TRUE))
    shares <- rast(shares)
    names(shares) <- names(land_types)
    writeRaster(shares, cache_file, overwrite = TRUE, datatype = "FLT4S",
                gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES"))
  }

  if (!file.exists(forest_file)) {
    forest <- round(rast(cache_file)[["forest"]] * 100)
    names(forest) <- paste0("clc", year, "_forest_pct")
    writeRaster(forest, forest_file, overwrite = TRUE, datatype = "INT1U",
                gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2", "ZLEVEL=9", "TILED=YES"))
  }
}

# Hectares of each land type by NUTS region. A 1 km cell has 100 hectares.
regions <- read_nuts_regions()

area_by_nuts <- bind_rows(lapply(years, \(year) {
  shares <- rast(file.path(cache_dir, sprintf("CLCACC%s_land_types_1km.tif", year)))
  sums <- extract(shares, vect(regions), fun = sum, na.rm = TRUE, ID = FALSE)
  regions |>
    st_drop_geometry() |>
    bind_cols(sums) |>
    tidyr::pivot_longer(all_of(names(land_types)), names_to = "land_type", values_to = "cells") |>
    transmute(epoch = as.integer(year), level, nuts_id, name, geo, land_type,
              hectares = replace(cells, is.na(cells), 0) * 100)
}))

saveRDS(area_by_nuts, file.path(out_dir, "clc_ecosystem_area_by_nuts.rds"))
