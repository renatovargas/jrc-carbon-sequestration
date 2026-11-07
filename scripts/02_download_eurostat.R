# Download the CO2 inventory by source sector.
#
# Why    : national removals and emissions of the land categories, and emissions of the economic sectors, come from it.
# Source : Eurostat dataset env_air_gge, "Greenhouse gas emissions by source sector (source: EEA)",
#          doi:10.2908/ENV_AIR_GGE, retrieved with the eurostat R package (SDMX API).
# Keeps  : airpol CO2, unit THS_T (thousand tonnes), all source sectors (src_crf), the 27 member
#          states and the EU27_2020 aggregate, years 1990 to 2024.
# Output : data/inputs/eurostat/env_air_gge_co2.rds (long format)
# Run    : source("scripts/02_download_eurostat.R", encoding = "UTF-8"), from the project root.
#          Needs internet access, and a new release of the dataset changes the results.

library(eurostat)
library(dplyr)

out_dir <- "data/inputs/eurostat"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

geos <- c(
  "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "EL", "HU",
  "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE",
  "EU27_2020"
)

raw <- get_eurostat(
  "env_air_gge", time_format = "num", cache = FALSE,
  filters = list(airpol = "CO2", unit = "THS_T")
)

env_air_gge_co2 <- raw |>
  filter(geo %in% geos, between(time, 1990, 2024)) |>
  transmute(
    geo,
    year = as.integer(time),
    src_crf,
    thousand_t_co2 = values
  ) |>
  # Keep rows with a reported value. Script 08 handles the gaps and lists them.
  filter(!is.na(thousand_t_co2)) |>
  arrange(src_crf, geo, year)

attr(env_air_gge_co2, "retrieved") <- format(Sys.time(), "%Y-%m-%d")

saveRDS(env_air_gge_co2, file.path(out_dir, "env_air_gge_co2.rds"))
