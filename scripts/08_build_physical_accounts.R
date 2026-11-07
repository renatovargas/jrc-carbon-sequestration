# Build the physical accounts by country and year.
#
# Why    : this is the calculation on tables that gives the actual flow, and it runs in seconds.
# Inputs : data/inputs/eurostat/env_air_gge_co2.rds (script 02)
#          data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg (script 01)
#          data/inputs/corine/clc_type_weight_by_nuts.rds (script 06)
# Outputs: data/outputs/results/carbon_lulucf_country_year.rds             which script 09 reads
#          data/outputs/results/carbon_flow_country_year.rds               which scripts 09 to 12 read
#          data/outputs/results/carbon_sector_allocation_country_year.rds
#          data/outputs/report/                                            small tables for the report
#          data/outputs/figures/carbon_eu_series.png, carbon_flow_country_2024.png
# Method : Removals and emissions come from the signed balance of six land categories. The EU net flow is attributed to
#          countries in proportion to their removals of forest land (La Notte et al., 2021, Equation 6.1). The script
#          stops if a check fails.
# Run    : source("scripts/08_build_physical_accounts.R", encoding = "UTF-8"), from the project root.

source("scripts/helpers_common.R", encoding = "UTF-8")
source("scripts/helpers_carbon.R", encoding = "UTF-8")

# Inputs. The 27 member states are kept, and the published EU27 aggregate is held aside for a check.
env_air_gge <- readRDS("data/inputs/eurostat/env_air_gge_co2.rds")
retrieved <- attr(env_air_gge, "retrieved")
countries <- sf::st_read("data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg", quiet = TRUE)
eu27 <- countries$geo[countries$eu27]
eu_aggregate <- env_air_gge |> filter(geo == "EU27_2020")
env_air_gge <- env_air_gge |> filter(geo %in% eu27)

# Signed balance, removals and emissions of each category.
lulucf <- signed_balance(
  env_air_gge,
  categories = c(lulucf_land, lulucf_memo),
  geos = eu27,
  years = years_all
) |>
  split_removals_emissions()

land <- lulucf |> filter(src_crf %in% names(lulucf_land))

# Check against the Eurostat aggregate.
eu_check <- env_air_gge |>
  filter(src_crf %in% c("CRF4", names(lulucf_land), names(lulucf_memo))) |>
  summarise(countries = sum(thousand_t_co2), .by = c(src_crf, year)) |>
  left_join(
    eu_aggregate |> select(src_crf, year, aggregate = thousand_t_co2),
    by = c("src_crf", "year")
  ) |>
  mutate(difference = countries - aggregate)

# The offset and the actual flow.
flow <- allocate_offset(land) |>
  mutate(
    flow_c = flow * co2_to_c,
    flow_no_offset_c = flow_no_offset * co2_to_c,
    missed_flow_c = missed_flow * co2_to_c
  )

flow_eu <- flow |>
  summarise(
    removals = sum(total_removals),
    emissions = sum(total_emissions),
    net_flow = sum(flow),
    missed_flow = sum(missed_flow),
    forest_removals = sum(forest_removals),
    .by = year
  )

# Allocation to the emitting sectors.
sectors <- allocate_to_sectors(flow, env_air_gge)

sector_totals <- sectors |>
  summarise(sum_of_sectors = sum(sector_emissions), .by = year) |>
  left_join(
    env_air_gge |>
      filter(src_crf == "TOTX4_MEMO") |>
      summarise(totx4 = sum(thousand_t_co2), .by = year),
    by = "year"
  )

# Checks, which stop the script on failure.
stopifnot(min(flow$flow) >= 0, min(flow$missed_flow) >= -1e-9)
forest_totals <- flow |> summarise(s = sum(forest_share), .by = year)
flow_totals <- flow |> summarise(f = sum(flow), net = first(eu_net), .by = year)
missed_totals <- flow |> filter(eu_net > 0) |> summarise(m = sum(missed_flow), e = first(eu_emissions), .by = year)
share_totals <- sectors |> summarise(s = sum(share), .by = c(geo, year))

checks <- bind_rows(
  record_check(forest_totals$s, 1, "Shares of the forest removals add up to one in every year"),
  record_check(flow_totals$f, flow_totals$net, "National flows add up to the EU net flow in every year"),
  record_check(missed_totals$m, missed_totals$e, "Missed flow adds up to the EU emissions in every year"),
  record_check(flow$flow_no_offset, flow$flow + flow$missed_flow, "Flow without offset equals actual flow plus missed flow",
               tolerance = 1e-9, relative = FALSE),
  record_check(share_totals$s, 1, "Sector shares add up to one in every country and year"),
  record_check(sector_totals$sum_of_sectors, sector_totals$totx4, "Sectors add up to total CO2 emissions without land use",
               tolerance = 5e-3),
  record_check(eu_check$countries, eu_check$aggregate, "Countries add up to the EU27 aggregate of Eurostat, in kt CO2",
               tolerance = 0.1, relative = FALSE)
)

# Exports.
save_table(
  lulucf |>
    transmute(
      geo, year, src_crf, category,
      in_flow = src_crf %in% names(lulucf_land),
      balance_kt_co2 = balance, removals_kt_co2 = removals, emissions_kt_co2 = emissions,
      balance_kt_c = balance * co2_to_c,
      missing_value = gap
    ),
  "carbon_lulucf_country_year"
)

save_table(
  flow |>
    transmute(
      geo, year,
      forest_removals_kt_co2 = forest_removals,
      removals_kt_co2 = total_removals,
      emissions_kt_co2 = total_emissions,
      national_balance_kt_co2 = national_balance,
      forest_share,
      eu_net_kt_co2 = eu_net,
      flow_kt_co2 = flow, flow_kt_c = flow_c,
      flow_no_offset_kt_co2 = flow_no_offset, flow_no_offset_kt_c = flow_no_offset_c,
      missed_flow_kt_co2 = missed_flow, missed_flow_kt_c = missed_flow_c
    ),
  "carbon_flow_country_year"
)

save_table(
  sectors |>
    transmute(geo, year, sector, sector_emissions_kt_co2 = sector_emissions, share, allocated_flow_kt_co2 = allocated_flow),
  "carbon_sector_allocation_country_year"
)

# Small tables for the report.
save_report_table(checks, "checks_physical")

type_weights <- readRDS("data/inputs/corine/clc_type_weight_by_nuts.rds")
save_report_table(
  tibble(
    countries = length(eu27),
    nuts2 = n_distinct(type_weights$nuts_id[type_weights$level == "NUTS2"]),
    nuts3 = n_distinct(type_weights$nuts_id[type_weights$level == "NUTS3"]),
    inventory_retrieved = retrieved
  ),
  "territory"
)
save_report_table(
  type_weights |> filter(fallback) |> distinct(epoch, geo, land_type) |> count(geo, land_type, name = "epochs"),
  "nuts_fallback"
)

save_report_table(
  lulucf |> filter(gap) |> count(src_crf, geo, name = "years_missing"),
  "category_gaps"
)
save_report_table(
  env_air_gge |> filter(src_crf == "CRF4H", year %in% years_all) |> summarise(countries = n_distinct(geo)),
  "residual_reporters"
)

save_report_table(
  lulucf |>
    filter(year %in% years_report) |>
    summarise(balance_mt = sum(balance) / 1000, .by = c(year, src_crf, category)),
  "balance_by_category"
)
save_report_table(
  land |>
    filter(year %in% years_report, src_crf == "CRF4A", balance < 0) |>
    transmute(year, geo, balance_kt = balance) |>
    arrange(year, balance_kt),
  "forest_sources"
)

save_report_table(
  env_air_gge |>
    filter(year %in% years_report, src_crf %in% c("CRF4", names(lulucf_land), names(lulucf_memo))) |>
    mutate(part = if_else(src_crf == "CRF4", "total", "parts")) |>
    summarise(value = sum(thousand_t_co2), .by = c(year, part)) |>
    pivot_wider(names_from = part, values_from = value) |>
    mutate(difference = total - parts),
  "crf4_check"
)

save_report_table(flow_eu, "eu_series")

# Published values: La Notte et al. (2021), Table 6.7, actual flow for the EU-28.
save_report_table(
  flow_eu |>
    filter(year %in% c(2000, 2006, 2012)) |>
    transmute(year, here_mt = net_flow / 1000) |>
    mutate(published_mt = c(291.554, 292.213, 306.308), difference_pct = 100 * (here_mt / published_mt - 1)),
  "published_flow"
)

save_report_table(
  flow |>
    filter(year %in% years_report) |>
    transmute(geo, year, flow, flow_no_offset, missed_flow, national_balance, forest_share, forest_removals),
  "flow_by_country"
)
save_report_table(
  flow |>
    filter(year %in% years_report) |>
    summarise(no_forest_removals = sum(forest_removals == 0), negative_balance = sum(national_balance < 0), .by = year),
  "country_counts"
)

save_report_table(
  sectors |>
    filter(year %in% years_report) |>
    summarise(allocated_mt = sum(allocated_flow) / 1000, .by = c(year, sector)),
  "sector_by_year"
)
save_report_table(
  env_air_gge |>
    summarise(
      parts = sum(thousand_t_co2[src_crf %in% sector_groups$src_crf]),
      total = sum(thousand_t_co2[src_crf == "TOTX4_MEMO"]),
      .by = c(geo, year)
    ) |>
    filter(year %in% years_all, abs(parts - total) > 1),
  "sector_gaps"
)

# Figures of the report.
figure_dir <- "data/outputs/figures"
line_figure(
  flow_eu |>
    transmute(year, Removals = removals / 1000, Emissions = emissions / 1000, `Actual flow` = net_flow / 1000) |>
    pivot_longer(-year, names_to = "series", values_to = "value"),
  y_label = "Million tonnes of CO2",
  path = file.path(figure_dir, "carbon_eu_series.png")
)

country_2024 <- flow |>
  filter(year == 2024) |>
  mutate(geo = reorder(geo, flow)) |>
  transmute(geo, `Actual flow` = flow / 1000, `Flow without offset` = flow_no_offset / 1000) |>
  pivot_longer(-geo, names_to = "series", values_to = "value")
figure <- ggplot2::ggplot(country_2024, ggplot2::aes(value, geo, fill = series)) +
  ggplot2::geom_col(position = ggplot2::position_dodge2(padding = 0.1, reverse = TRUE), width = 0.82) +
  ggplot2::scale_fill_manual(values = series_colours, name = NULL) +
  ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0, 0.03))) +
  ggplot2::labs(x = "Million tonnes of CO2, 2024", y = NULL) +
  theme_figures() +
  ggplot2::theme(panel.grid.major.y = ggplot2::element_blank())
ggplot2::ggsave(file.path(figure_dir, "carbon_flow_country_2024.png"), figure, width = 7, height = 6.2, dpi = 200, bg = "white")
