# Write the 100 m maps of carbon sequestration, namely the flow without offset, the actual flow, the missed flow and their value.
#
# Why    : the 100 m maps are a product of the accounts, and they are too large to version, so they go to
#          refs/maps_100m/ and are published outside the repository.
# Inputs : refs/clc_accounting/CLC<year>ACC_V2024_21.tif (CLC accounting layers at 100 m, CLC codes)
#          refs/gdmp_annual/gdmp_<product>_<year>_4326.tif (annual productivity, script 05)
#          data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg (script 01)
#          data/outputs/results/carbon_flow_country_year.rds (script 08)
#          data/outputs/results/carbon_value_country_year.rds (script 09)
# Outputs: refs/maps_100m/carbon_flow_gdmp_100m_<year>.tif             (thousand tonnes of CO2 per cell)
#          refs/maps_100m/carbon_flow_no_offset_gdmp_100m_<year>.tif   (thousand tonnes of CO2 per cell, forest land removals)
#          refs/maps_100m/carbon_value_constant_gdmp_100m_<year>.tif   (million euro, 2010 prices, per cell)
#          refs/maps_100m/carbon_missed_flow_gdmp_100m_<year>.tif     (thousand tonnes of CO2 per cell)
#          refs/maps_100m/carbon_missed_value_constant_gdmp_100m_<year>.tif (million euro, 2010 prices, per cell)
# Method : The weight of a 100 m cell is 1 for forest (CLC 311, 312, 313 and 324) and 0 otherwise, times the annual
#          productivity of the year resampled to 100 m (bilinear). Each cell receives the national value
#          times its weight divided by the weight total of its country, so the cells of a country add up to
#          the national total. Productivity of 2000, 2006 and 2012 comes from the 1 km product, and that of
#          2018 and 2024 from the 300 m product. The value map is the flow map times the price per tonne of CO2
#          and the deflator of the year. The map of the flow without offset spreads the removals of forest land with
#          the same key, because the other land categories switch between source and sink. The missed flow is a balance with
#          no place of its own on the land, so its map allocates the national value with the same key.
# Run    : source("scripts/11_write_maps_100m.R", encoding = "UTF-8"), from the project root, after script 09.
#          Needs the files in refs/, takes about 45 minutes per year and needs several GB of free disk space for
#          temporary files. Maps that already exist are skipped, so delete them after a change in the tables.

library(terra)
library(dplyr)

clc_dir <- "refs/clc_accounting"
gdmp_dir <- "refs/gdmp_annual"
out_dir <- "refs/maps_100m"
tmp_dir <- "refs/maps_100m_tmp"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(tmp_dir, showWarnings = FALSE, recursive = TRUE)

# Temporary rasters of this size do not fit in /tmp, which is held in memory on some machines.
terraOptions(tempdir = tmp_dir, progress = 0)

years_report <- c(2000, 2006, 2012, 2018, 2024)
gdmp_product <- c(`2000` = "1km", `2006` = "1km", `2012` = "1km", `2018` = "300m", `2024` = "300m")
forest_codes <- c(311, 312, 313, 324)
gdal_opts <- c("COMPRESS=DEFLATE", "PREDICTOR=3", "ZLEVEL=6", "TILED=YES")

flow <- readRDS("data/outputs/results/carbon_flow_country_year.rds")
value <- readRDS("data/outputs/results/carbon_value_country_year.rds")
price_factor <- value |>
  distinct(year, factor = price_eur_per_t_co2 * deflator / 1000)

# Same extent as the 1 km maps, at 100 m, aligned with the CLC grid
template <- rast(
  xmin = 2636000, xmax = 7317000, ymin = 1385900, ymax = 5415900,
  resolution = 100, crs = "EPSG:3035"
)

countries <- vect("data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg")
countries <- countries[countries$eu27, ]
countries$id <- seq_len(nrow(countries))
ids <- rasterize(countries, template, field = "id", filename = file.path(tmp_dir, "ids.tif"), overwrite = TRUE)
id_table <- tibble(id = countries$id, geo = countries$geo)

for (yr in years_report) {
  flow_file <- file.path(out_dir, sprintf("carbon_flow_gdmp_100m_%s.tif", yr))
  value_file <- file.path(out_dir, sprintf("carbon_value_constant_gdmp_100m_%s.tif", yr))
  no_offset_file <- file.path(out_dir, sprintf("carbon_flow_no_offset_gdmp_100m_%s.tif", yr))
  missed_file <- file.path(out_dir, sprintf("carbon_missed_flow_gdmp_100m_%s.tif", yr))
  missed_value_file <- file.path(out_dir, sprintf("carbon_missed_value_constant_gdmp_100m_%s.tif", yr))
  if (all(file.exists(c(flow_file, value_file, no_offset_file, missed_file, missed_value_file)))) next

  clc <- crop(rast(file.path(clc_dir, sprintf("CLC%sACC_V2024_21.tif", yr))), template)
  levels(clc) <- NULL
  coltab(clc) <- NULL
  forest <- ifel(clc %in% forest_codes & !is.na(ids), 1, 0)

  gdmp <- rast(file.path(gdmp_dir, sprintf("gdmp_%s_%s_4326.tif", gdmp_product[[as.character(yr)]], yr)))
  gdmp100 <- project(gdmp, template, method = "bilinear")
  weight <- forest * ifel(is.na(gdmp100), 0, gdmp100)
  weight <- writeRaster(weight, file.path(tmp_dir, sprintf("weight_%s.tif", yr)),
                        datatype = "FLT4S", overwrite = TRUE,
                        gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES"))

  sums <- zonal(weight, ids, fun = "sum", na.rm = TRUE) |>
    setNames(c("id", "weight_sum")) |>
    inner_join(id_table, by = "id")

  # Spread one national column over the forest cells, and write the map unless it already exists.
  write_spread <- function(column, path, layer) {
    if (file.exists(path)) return(invisible(path))
    per_weight <- id_table |>
      left_join(sums, by = c("id", "geo")) |>
      left_join(flow |> filter(year == yr) |> transmute(geo, total = .data[[column]]), by = "geo") |>
      mutate(per_weight = if_else(weight_sum > 0, total / weight_sum, NA_real_)) |>
      filter(!is.na(per_weight))
    spread <- weight * classify(ids, rcl = as.matrix(per_weight[, c("id", "per_weight")]), others = NA)
    names(spread) <- layer
    writeRaster(spread, path, overwrite = TRUE, datatype = "FLT4S", gdal = gdal_opts)
    invisible(path)
  }
  # Value maps are the physical map, read back from disk, times the price per tonne of CO2 and the deflator.
  write_value <- function(physical_file, path, layer) {
    if (file.exists(path)) return(invisible(path))
    value_map <- rast(physical_file) * price_factor$factor[price_factor$year == yr]
    names(value_map) <- layer
    writeRaster(value_map, path, overwrite = TRUE, datatype = "FLT4S", gdal = gdal_opts)
    invisible(path)
  }

  write_spread("flow_kt_co2", flow_file, paste0("carbon_flow_", yr))
  write_value(flow_file, value_file, paste0("carbon_value_constant_", yr))
  write_spread("forest_removals_kt_co2", no_offset_file, paste0("carbon_flow_no_offset_", yr))
  write_spread("missed_flow_kt_co2", missed_file, paste0("carbon_missed_flow_", yr))
  write_value(missed_file, missed_value_file, paste0("carbon_missed_value_constant_", yr))

  unlink(file.path(tmp_dir, sprintf("weight_%s.tif", yr)))
}

unlink(tmp_dir, recursive = TRUE)
