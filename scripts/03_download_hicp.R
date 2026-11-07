# Download the consumer price index of the European Union.
#
# Why    : the index moves the carbon price between years and gives the constant prices.
# Source : Eurostat dataset prc_hicp_aind, harmonised index of consumer prices, annual average
#          index (2015 = 100), all items, EU27 (2020 composition). Retrieved with the eurostat R package.
# Output : data/inputs/eurostat/hicp_eu27.rds
# Run    : source("scripts/03_download_hicp.R", encoding = "UTF-8"), from the project root.
#          Needs internet access, and a new release of the dataset changes the results.

library(eurostat)
library(dplyr)

out_dir <- "data/inputs/eurostat"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

hicp <- get_eurostat(
  "prc_hicp_aind", time_format = "num", cache = FALSE,
  filters = list(geo = "EU27_2020", coicop = "CP00", unit = "INX_A_AVG")
) |>
  transmute(year = as.integer(time), hicp_2015 = values) |>
  arrange(year)

saveRDS(hicp, file.path(out_dir, "hicp_eu27.rds"))
