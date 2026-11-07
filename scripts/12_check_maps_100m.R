# Check the 100 m maps against the national tables, reading the maps back from disk.
#
# Why    : the 100 m maps live outside the repository, so this script records that the cells of each country still add
#          up to its national value, and the report reads that record.
# Inputs : refs/maps_100m/carbon_flow_gdmp_100m_<year>.tif and carbon_value_constant_gdmp_100m_<year>.tif (script 11)
#          refs/maps_100m/carbon_flow_no_offset_gdmp_100m_<year>.tif (script 11)
#          refs/maps_100m/carbon_missed_flow_gdmp_100m_<year>.tif and carbon_missed_value_constant_gdmp_100m_<year>.tif (script 11)
#          data/outputs/results/carbon_flow_country_year.rds (script 08)
#          data/outputs/results/carbon_value_country_year.rds (script 09)
#          data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg (script 01)
# Outputs: data/outputs/report/maps_100m_totals.rds, with the total of every map and table by year
#          data/outputs/report/checks_maps_100m.rds
# Method : Each map is added up by country in blocks, one map at a time, so little memory is needed. The script stops
#          if a country or a year disagrees with the tables.
# Run    : source("scripts/12_check_maps_100m.R", encoding = "UTF-8"), from the project root, after script 11. Needs the
#          files in refs/, and takes about 15 minutes in total.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_carbon.R", encoding = "UTF-8")

work_dir <- "refs/maps_100m_check"
dir.create(work_dir, showWarnings = FALSE, recursive = TRUE)
terraOptions(tempdir = work_dir, progress = 0)

flow <- readRDS("data/outputs/results/carbon_flow_country_year.rds")
value <- readRDS("data/outputs/results/carbon_value_country_year.rds")

template <- rast(
  xmin = 2636000, xmax = 7317000, ymin = 1385900, ymax = 5415900,
  resolution = 100, crs = "EPSG:3035"
)
countries <- vect("data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg")
countries <- countries[countries$eu27, ]
countries$id <- seq_len(nrow(countries))
ids <- rasterize(countries, template, field = "id", filename = file.path(work_dir, "ids.tif"), overwrite = TRUE)
id_table <- tibble(id = countries$id, geo = countries$geo)

#' Add up one map by country.
sum_by_country <- function(path, yr, quantity) {
  message("Adding up ", path, ", ", format(Sys.time()))
  zonal(rast(path), ids, fun = "sum", na.rm = TRUE) |>
    setNames(c("id", "map")) |>
    inner_join(id_table, by = "id") |>
    transmute(geo, year = yr, quantity, map)
}

maps <- bind_rows(lapply(years_report, \(yr) {
  bind_rows(
    sum_by_country(sprintf("refs/maps_100m/carbon_flow_gdmp_100m_%s.tif", yr), yr, "flow_kt_co2"),
    sum_by_country(sprintf("refs/maps_100m/carbon_value_constant_gdmp_100m_%s.tif", yr), yr, "value_meur2010"),
    sum_by_country(sprintf("refs/maps_100m/carbon_flow_no_offset_gdmp_100m_%s.tif", yr), yr, "forest_removals_kt_co2"),
    sum_by_country(sprintf("refs/maps_100m/carbon_missed_flow_gdmp_100m_%s.tif", yr), yr, "missed_flow_kt_co2"),
    sum_by_country(sprintf("refs/maps_100m/carbon_missed_value_constant_gdmp_100m_%s.tif", yr), yr, "missed_value_meur2010")
  )
}))

tables <- bind_rows(
  flow |> filter(year %in% years_report) |> transmute(geo, year, quantity = "flow_kt_co2", table = flow_kt_co2),
  value |> filter(year %in% years_report) |> transmute(geo, year, quantity = "value_meur2010", table = value_constant_meur),
  flow |> filter(year %in% years_report) |> transmute(geo, year, quantity = "forest_removals_kt_co2", table = forest_removals_kt_co2),
  flow |> filter(year %in% years_report) |> transmute(geo, year, quantity = "missed_flow_kt_co2", table = missed_flow_kt_co2),
  value |> filter(year %in% years_report) |> transmute(geo, year, quantity = "missed_value_meur2010", table = missed_value_constant_meur)
)

compared <- tables |>
  left_join(maps, by = c("geo", "year", "quantity")) |>
  mutate(map = coalesce(map, 0))
positive <- compared |> filter(table > 0)

totals <- compared |>
  summarise(map = sum(map), table = sum(table), .by = c(quantity, year)) |>
  mutate(difference_pct = 100 * (map / table - 1))

checks <- bind_rows(
  record_check(positive$map, positive$table, "100 m maps against the tables, in every country and year", tolerance = 1e-4),
  record_check(totals$map, totals$table, "100 m maps against the tables, in every year", tolerance = 1e-4)
)

save_report_table(totals, "maps_100m_totals")
save_report_table(checks, "checks_maps_100m")

unlink(work_dir, recursive = TRUE)
