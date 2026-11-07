# Value the physical accounts with the social cost of carbon.
#
# Why    : this is the calculation on tables that follows the physical accounts, and it runs in seconds.
# Inputs : data/outputs/results/carbon_flow_country_year.rds and carbon_lulucf_country_year.rds (script 08)
#          data/inputs/prices/carbon_price.rds (script 07)
#          data/inputs/eurostat/hicp_eu27.rds (script 03)
#          data/inputs/corine/clc_type_weight_by_nuts.rds (script 06)
# Outputs: data/outputs/results/carbon_value_country_year.rds            which scripts 10 and 11 read
#          data/outputs/results/carbon_sequestration_results.xlsx      workbook by NUTS level, physical and monetary
#          data/outputs/report/                                        small tables for the report
#          data/outputs/figures/carbon_value_series.png
# Method : Value is the flow in tonnes of CO2 times the price per tonne, in current prices, and times the deflator
#          in constant prices. The script stops if a check fails.
# Run    : source("scripts/09_build_monetary_accounts.R", encoding = "UTF-8"), from the project root, after script 08.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_carbon.R", encoding = "UTF-8")
source("scripts/helpers_monetary.R", encoding = "UTF-8")
source("scripts/helpers_results.R", encoding = "UTF-8")

results_dir <- "data/outputs/results"

carbon_price <- readRDS("data/inputs/prices/carbon_price.rds")
deflator <- make_deflator(readRDS("data/inputs/eurostat/hicp_eu27.rds"), "hicp_2015", base_year)
flow <- readRDS(file.path(results_dir, "carbon_flow_country_year.rds"))
type_weights <- readRDS("data/inputs/corine/clc_type_weight_by_nuts.rds")

value <- flow |>
  select(geo, year, flow_kt_co2, flow_no_offset_kt_co2, missed_flow_kt_co2) |>
  left_join(carbon_price |> select(year, price_eur_per_t_co2), by = "year") |>
  left_join(deflator, by = "year") |>
  mutate(
    value_current_meur = flow_kt_co2 * price_eur_per_t_co2 / 1000,
    value_constant_meur = value_current_meur * deflator,
    value_no_offset_current_meur = flow_no_offset_kt_co2 * price_eur_per_t_co2 / 1000,
    value_no_offset_constant_meur = value_no_offset_current_meur * deflator,
    missed_value_current_meur = missed_flow_kt_co2 * price_eur_per_t_co2 / 1000,
    missed_value_constant_meur = missed_value_current_meur * deflator
  )

value_table <- value |>
  transmute(
    geo, year, flow_kt_co2, flow_no_offset_kt_co2, missed_flow_kt_co2,
    price_eur_per_t_co2, deflator,
    value_current_meur, value_constant_meur,
    value_no_offset_current_meur, value_no_offset_constant_meur,
    missed_value_current_meur, missed_value_constant_meur
  )

# Regional values of the reporting years.
removals_by_type <- readRDS(file.path(results_dir, "carbon_lulucf_country_year.rds")) |>
  filter(in_flow) |>
  mutate(land_type = recode(src_crf, CRF4A = "forest", CRF4B = "cropland", CRF4C = "grassland",
                            CRF4D = "wetlands", CRF4E = "settlements", CRF4F = "other_land")) |>
  select(geo, year, land_type, removals = removals_kt_co2) |>
  pivot_wider(names_from = land_type, values_from = removals, names_prefix = "rem_")

national_for_workbook <- flow |>
  transmute(
    geo, year, flow = flow_kt_co2, flow_no_offset = flow_no_offset_kt_co2,
    missed_flow = missed_flow_kt_co2, removals = removals_kt_co2,
    emissions = emissions_kt_co2, balance = national_balance_kt_co2
  ) |>
  left_join(removals_by_type, by = c("geo", "year")) |>
  left_join(
    value |> distinct(year, price = price_eur_per_t_co2, deflator),
    by = "year"
  )

regional <- regional_results(national_for_workbook, type_weights, years = years_report, epochs = clc_for_year)
region_checks <- results_checks(regional)

# Checks, which stop the script on failure.
stopifnot(all(value$value_current_meur >= 0), all(carbon_price$price_eur_per_t_co2 > 0), all(region_checks$match))
checks <- bind_rows(
  record_check(deflator$deflator[deflator$year == base_year], 1, "The deflator equals one in the base year", tolerance = 1e-12),
  record_check(value$value_constant_meur, value$value_current_meur * value$deflator,
               "Constant values equal current values times the deflator", tolerance = 1e-9, relative = FALSE),
  record_check(value$value_no_offset_current_meur, value$value_current_meur + value$missed_value_current_meur,
               "Actual value plus missed value equals the value without offset", tolerance = 1e-9, relative = FALSE),
  record_check(region_checks$regional_total, region_checks$national_total,
               "NUTS2 and NUTS3 regions add up to the countries, in every table, metric and year")
)

# Exports.
save_table(value_table, "carbon_value_country_year")

write_carbon_results_workbook(
  regional,
  years = years_report,
  base_year = base_year,
  path = file.path(results_dir, "carbon_sequestration_results.xlsx")
)

# Small tables for the report.
save_report_table(checks, "checks_monetary")
save_report_table(
  carbon_price |>
    filter(year %in% years_report) |>
    select(year, price_2023 = price_eur_per_t_co2_2023, price_current = price_eur_per_t_co2),
  "carbon_price"
)
save_report_table(deflator |> filter(year %in% c(years_report, base_year)) |> arrange(year), "deflators")

value_eu <- value |>
  summarise(
    flow_mt = sum(flow_kt_co2) / 1000,
    current = sum(value_current_meur),
    constant = sum(value_constant_meur),
    missed_constant = sum(missed_value_constant_meur),
    no_offset_constant = sum(value_no_offset_constant_meur),
    .by = year
  )
save_report_table(value_eu, "value_eu_series")

save_report_table(
  value |>
    filter(year %in% years_report) |>
    select(geo, year, value_current_meur, value_constant_meur, missed_value_constant_meur),
  "value_by_country"
)

# Published value and implied price: La Notte et al. (2021), Table 6.7, 2012, EU-28.
save_report_table(
  value |>
    filter(year == 2012) |>
    summarise(flow = sum(flow_kt_co2), value = sum(value_current_meur)) |>
    transmute(price_here = value / flow * 1000, price_published = 9189 / 306308 * 1000),
  "benchmark_2012"
)

# The regions with the largest values, to show what the workbook holds.
save_report_table(
  regional |>
    filter(year == 2024, level == "NUTS2") |>
    slice_max(flow, n = 10) |>
    select(nuts_id, name, flow, flow_no_offset, missed_flow, flow_constant),
  "top_regions_2024"
)

# Figure of the report.
line_figure(
  value_eu |>
    transmute(year, `Actual flow` = constant, `Missed flow` = missed_constant) |>
    pivot_longer(-year, names_to = "series", values_to = "value"),
  y_label = "Million euro, constant 2010 prices",
  path = "data/outputs/figures/carbon_value_series.png"
)
