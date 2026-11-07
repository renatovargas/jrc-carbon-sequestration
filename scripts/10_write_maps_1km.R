# Write the 1 km maps of the actual flow and of its value, and the figures and checks that depend on them.
#
# Why    : the maps place the national flow on forest, and they only need to run again when the tables or the key change.
# Inputs : data/outputs/results/carbon_flow_country_year.rds (script 08)
#          data/outputs/results/carbon_value_country_year.rds (script 09)
#          data/inputs/corine/CLC<year>_forest_pct_1km.tif and clc_ecosystem_area_by_nuts.rds (script 04)
#          data/inputs/gdmp/GDMP_<year>_1km.tif (script 05)
#          data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg (script 01)
# Outputs: refs/maps_1km/carbon_flow_gdmp_1km_<year>.tif             (thousand tonnes of CO2 per cell)
#          refs/maps_1km/carbon_value_constant_gdmp_1km_<year>.tif   (million euro, 2010 prices, per cell)
#          refs/maps_1km/carbon_flow_no_offset_gdmp_1km_<year>.tif     (thousand tonnes of CO2 per cell, forest land removals)
#          data/outputs/report/                                      small tables for the report
#          data/outputs/figures/carbon_flow_maps.png, carbon_value_maps.png
# Method : The weight of a cell is its forest share times its annual productivity. Each cell receives the national value
#          times its weight divided by the weight total of its country. The script reads the maps back from disk and
#          stops if they disagree with the tables.
# Run    : source("scripts/10_write_maps_1km.R", encoding = "UTF-8"), from the project root, after script 09.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_carbon.R", encoding = "UTF-8")
library(sf)

gis_dir <- "refs/maps_1km"
dir.create(gis_dir, showWarnings = FALSE, recursive = TRUE)
gdal_options <- c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES")

flow <- readRDS("data/outputs/results/carbon_flow_country_year.rds")
value <- readRDS("data/outputs/results/carbon_value_country_year.rds")
countries_file <- "data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg"
countries <- st_read(countries_file, quiet = TRUE)

# The weights of each reporting year.
forest_share <- lapply(years_report, read_forest_share)
productivity <- lapply(years_report, \(y) rast(sprintf("data/inputs/gdmp/GDMP_%s_1km.tif", y)))
weights <- Map(\(f, p) f * p, forest_share, productivity)
names(forest_share) <- names(productivity) <- names(weights) <- years_report

eu_countries <- vect(countries_file)
eu_countries <- eu_countries[eu_countries$eu27, ]
country_ids <- make_country_ids(eu_countries, forest_share[["2018"]])
weight_sums <- lapply(weights, country_weight_sums, country_ids = country_ids)

# Flow maps. The value maps read them back, so they use the stored values.
for (yr in years_report) {
  epoch <- as.character(yr)
  flow_map <- spread_totals(
    totals = flow |> filter(year == yr) |> transmute(geo, value = flow_kt_co2),
    weight = weights[[epoch]],
    country_ids = country_ids,
    weight_sums = weight_sums[[epoch]]
  )
  names(flow_map) <- paste0("carbon_flow_", yr)
  writeRaster(flow_map, file.path(gis_dir, sprintf("carbon_flow_gdmp_1km_%s.tif", yr)),
              overwrite = TRUE, datatype = "FLT4S", gdal = gdal_options)
}

# Flow without offset, which maps the removals of forest land because the other categories switch between source and
# sink from year to year and country to country. It uses the same key as the actual flow.
for (yr in years_report) {
  epoch <- as.character(yr)
  no_offset_map <- spread_totals(
    totals = flow |> filter(year == yr) |> transmute(geo, value = forest_removals_kt_co2),
    weight = weights[[epoch]],
    country_ids = country_ids,
    weight_sums = weight_sums[[epoch]]
  )
  names(no_offset_map) <- paste0("carbon_flow_no_offset_", yr)
  writeRaster(no_offset_map, file.path(gis_dir, sprintf("carbon_flow_no_offset_gdmp_1km_%s.tif", yr)),
              overwrite = TRUE, datatype = "FLT4S", gdal = gdal_options)
}

for (yr in years_report) {
  flow_map <- rast(file.path(gis_dir, sprintf("carbon_flow_gdmp_1km_%s.tif", yr)))
  factor_year <- value |> filter(year == yr) |> slice(1) |> mutate(f = price_eur_per_t_co2 * deflator / 1000) |> pull(f)
  value_map <- flow_map * factor_year
  names(value_map) <- paste0("carbon_value_constant_", yr)
  writeRaster(value_map, file.path(gis_dir, sprintf("carbon_value_constant_gdmp_1km_%s.tif", yr)),
              overwrite = TRUE, datatype = "FLT4S", gdal = gdal_options)
}

flow_maps <- rast(file.path(gis_dir, sprintf("carbon_flow_gdmp_1km_%s.tif", years_report)))
value_maps <- rast(file.path(gis_dir, sprintf("carbon_value_constant_gdmp_1km_%s.tif", years_report)))
no_offset_maps <- rast(file.path(gis_dir, sprintf("carbon_flow_no_offset_gdmp_1km_%s.tif", years_report)))

# Checks, which read the maps back from disk and stop the script on failure.
national_flow <- flow |> filter(year %in% years_report) |> summarise(v = sum(flow_kt_co2), .by = year)
national_value <- value |> filter(year %in% years_report) |> summarise(v = sum(value_constant_meur), .by = year)
national_forest <- flow |> filter(year %in% years_report) |> summarise(v = sum(forest_removals_kt_co2), .by = year)
map_totals <- tibble(
  year = years_report,
  flow_map_mt = global(flow_maps, "sum", na.rm = TRUE)[[1]] / 1000,
  flow_table_mt = national_flow$v[match(years_report, national_flow$year)] / 1000,
  value_map_meur = global(value_maps, "sum", na.rm = TRUE)[[1]],
  value_table_meur = national_value$v[match(years_report, national_value$year)],
  no_offset_map_mt = global(no_offset_maps, "sum", na.rm = TRUE)[[1]] / 1000,
  forest_removals_mt = national_forest$v[match(years_report, national_forest$year)] / 1000
)

by_country <- bind_rows(lapply(years_report, \(yr) {
  zonal(flow_maps[[paste0("carbon_flow_", yr)]], country_ids$raster, fun = "sum", na.rm = TRUE) |>
    setNames(c("id", "map")) |>
    left_join(country_ids$ids, by = "id") |>
    transmute(geo, year = yr, map)
})) |>
  right_join(flow |> filter(year %in% years_report) |> select(geo, year, table = flow_kt_co2), by = c("geo", "year")) |>
  mutate(map = coalesce(map, 0))

checks <- bind_rows(
  record_check(map_totals$flow_map_mt, map_totals$flow_table_mt, "1 km flow maps against the tables, in every year", tolerance = 1e-5),
  record_check(map_totals$value_map_meur, map_totals$value_table_meur, "1 km value maps against the tables, in every year", tolerance = 1e-5),
  record_check(map_totals$no_offset_map_mt, map_totals$forest_removals_mt, "1 km maps of forest removals against the tables, in every year", tolerance = 1e-5),
  record_check(by_country$map[by_country$table > 0], by_country$table[by_country$table > 0],
               "1 km flow maps against the tables, in every country and year", tolerance = 1e-5)
)

# Countries with a flow but no forest cells would lose it in the map.
lost <- flow |>
  filter(year %in% years_report, flow_kt_co2 > 0) |>
  mutate(epoch = as.character(clc_for_year[as.character(year)])) |>
  rowwise() |>
  mutate(weight_sum = weight_sums[[epoch]]$weight_sum[match(geo, weight_sums[[epoch]]$geo)]) |>
  ungroup() |>
  filter(is.na(weight_sum) | weight_sum <= 0) |>
  select(year, geo, flow_kt_co2)

# Small tables for the report.
save_report_table(checks, "checks_maps")
save_report_table(map_totals, "map_totals")
save_report_table(lost, "countries_without_forest")

clc_area <- readRDS("data/inputs/corine/clc_ecosystem_area_by_nuts.rds")
save_report_table(
  bind_rows(lapply(forest_share, country_weight_sums, country_ids = country_ids), .id = "epoch") |>
    summarise(grid_mha = sum(weight_sum) * 100 / 1e6, .by = epoch) |>
    left_join(
      clc_area |>
        filter(level == "NUTS0", land_type == "forest") |>
        summarise(table_mha = sum(hectares) / 1e6, .by = epoch) |>
        mutate(epoch = as.character(epoch)),
      by = "epoch"
    ),
  "forest_area"
)
save_report_table(
  tibble(
    year = years_report,
    mean_gdmp_on_forest = sapply(as.character(years_report), \(y) {
      global(mask(productivity[[y]], forest_share[[y]] > 0.5, maskvalues = FALSE), "mean", na.rm = TRUE)[[1]]
    })
  ),
  "gdmp_on_forest"
)

# Figures of the report, at 10 km, where each tile is the sum of 100 cells of 1 km.
map_figure(flow_maps, "carbon_flow_", countries, "kt CO2\nper 10 km cell", "data/outputs/figures/carbon_flow_maps.png")
map_figure(value_maps, "carbon_value_constant_", countries, "Million euro\nper 10 km cell", "data/outputs/figures/carbon_value_maps.png")
