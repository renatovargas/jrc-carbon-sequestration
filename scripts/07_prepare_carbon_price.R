# Prepare the carbon price series of the monetary accounts.
#
# Why    : the valuation needs a price per tonne of CO2 in the euros of each year.
# Source : Social cost of carbon (SCC) based on Tol (2023), at EUR 343.6 per tonne of carbon (C) in 2023 euros, so the
#          price per tonne of CO2 is 343.6 * 12/44. The derivation and its sources are in research/carbon-price.md.
# Method : The SCC is a single real value. It is held constant in 2023 euros for every year, so the price
#          of year t in euros of that year is the 2023 value times HICP(t) / HICP(2023). Constant 2010
#          prices follow from the deflator in script 09.
# Input  : data/inputs/eurostat/hicp_eu27.rds (script 03)
# Output : data/inputs/prices/carbon_price.rds
#          One row per year 2000 to 2024 with the price in euro per tonne of CO2 in current prices
#          and in 2023 prices, and the source.
# Run    : source("scripts/07_prepare_carbon_price.R", encoding = "UTF-8"), from the project root.

library(dplyr)

out_dir <- "data/inputs/prices"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

scc_eur_per_t_c_2023 <- 343.6
price_year <- 2023
scc_eur_per_t_co2_2023 <- scc_eur_per_t_c_2023 * 12 / 44

hicp <- readRDS("data/inputs/eurostat/hicp_eu27.rds")
hicp_price_year <- hicp$hicp_2015[hicp$year == price_year]

carbon_price <- hicp |>
  filter(between(year, 2000, 2024)) |>
  transmute(
    year,
    price_eur_per_t_co2_2023 = scc_eur_per_t_co2_2023,
    price_eur_per_t_co2 = scc_eur_per_t_co2_2023 * hicp_2015 / hicp_price_year,
    source = "Social cost of carbon, EUR 343.6 per tonne of C in 2023 euros (Tol, 2023), converted to CO2 at 12/44",
    price_basis = "Real value held constant in 2023 euros, current price of each year by HICP"
  )

saveRDS(carbon_price, file.path(out_dir, "carbon_price.rds"))
