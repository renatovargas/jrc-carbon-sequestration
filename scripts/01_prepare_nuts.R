# Prepare the country boundaries of the accounts.
#
# Why    : the maps and tables need the 27 member states, and the full boundary file is too large for the repository.
# Input  : refs/INCA_plugin/src/inca/data/NUTS_RG_01M_2024_3035_LEVL0123_INCA.gpkg
#          (Eurostat GISCO NUTS 2024, scale 1:1 million, EPSG:3035, as distributed with the INCA plugin)
# Outputs: data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg  (country level only)
#          data/inputs/gis/README_NUTS.txt                   (copyright notice to reproduce)
# Run    : source("scripts/01_prepare_nuts.R", encoding = "UTF-8"), from the project root. Needs the file in refs/.

library(sf)
library(dplyr)

source_gpkg <- "refs/INCA_plugin/src/inca/data/NUTS_RG_01M_2024_3035_LEVL0123_INCA.gpkg"
source_readme <- "refs/INCA_plugin/src/inca/data/README_NUTS.txt"
out_dir <- "data/inputs/gis"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# EU27 country codes in Eurostat convention (EL for Greece)
eu27 <- c(
  "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "EL", "HU",
  "IE", "IT", "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE"
)

countries <- st_read(source_gpkg, layer = "NUTS_RG_01M_2024_3035.gpkg", quiet = TRUE) |>
  filter(LEVL_CODE == 0) |>
  transmute(
    geo = NUTS_ID,
    country = NAME_LATN,
    eu27 = NUTS_ID %in% eu27
  ) |>
  arrange(geo)

stopifnot(sum(countries$eu27) == 27)

st_write(
  countries,
  file.path(out_dir, "NUTS_RG_01M_2024_3035_LEVL0.gpkg"),
  layer = "countries",
  delete_dsn = TRUE,
  quiet = TRUE
)
file.copy(source_readme, file.path(out_dir, "README_NUTS.txt"), overwrite = TRUE)
