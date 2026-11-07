# Helper functions of the carbon accounts, used by the numbered scripts.
# Load with: source("scripts/helpers_carbon.R", encoding = "UTF-8")
# Values are thousand tonnes of CO2. Uptake is positive and emission is negative in the signed balance.

library(dplyr)
library(tidyr)

# The series covers every year, and maps and regional tables cover the reporting years.
years_all <- 2000:2024
years_report <- c(2000, 2006, 2012, 2018, 2024)

# Corine accounting layer and productivity year used for each reporting year
clc_for_year <- c(`2000` = 2000, `2006` = 2006, `2012` = 2012, `2018` = 2018, `2024` = 2024)

# Base year of the constant prices
base_year <- 2010

# Share of carbon in CO2 by mass (12 / 44)
co2_to_c <- 12 / 44

# LULUCF categories of the inventory that enter the flow, and the memo categories that stay outside
lulucf_land <- c(
  CRF4A = "Forest land", CRF4B = "Cropland", CRF4C = "Grassland",
  CRF4D = "Wetlands", CRF4E = "Settlements", CRF4F = "Other land"
)
lulucf_memo <- c(CRF4G = "Harvested wood products", CRF4H = "Other")

# Emitting sectors, as groups of CRF categories that add up to TOTX4_MEMO
sector_groups <- tribble(
  ~src_crf,        ~sector,
  "CRF1A1",        "Energy supply",
  "CRF1B",         "Energy supply",
  "CRF1C",         "Energy supply",
  "CRF1A2",        "Manufacturing and construction",
  "CRF2",          "Manufacturing and construction",
  "CRF1A3",        "Transport",
  "CRF1A4C",       "Agriculture, forestry and fishing",
  "CRF3",          "Agriculture, forestry and fishing",
  "CRF1A4B",       "Households",
  "CRF1A4A",       "Services and other",
  "CRF1A5",        "Services and other",
  "CRF6",          "Services and other",
  "CRF_INDCO2",    "Services and other",
  "CRF5",          "Waste"
)

# Colours of the figures. Each series keeps its colour in every figure, and the set is checked for colour blindness.
series_colours <- c(
  Removals = "#2a78d6", `Flow without offset` = "#2a78d6", Emissions = "#eb6834", `Missed flow` = "#eb6834",
  `Actual flow` = "#1baf7a"
)

#' Common look of the figures of the report.
theme_figures <- function() {
  ggplot2::theme_minimal(base_size = 10) +
    ggplot2::theme(panel.grid.minor = ggplot2::element_blank(), legend.position = "top", legend.justification = "left")
}

#' Draw a line for each series, with a legend and a direct label at the end of each line.
#'
#' @param data Table with year, series and value.
#' @param y_label Label of the vertical axis.
#' @param path Output file.
line_figure <- function(data, y_label, path) {
  labels <- data |> filter(year == max(year))
  figure <- ggplot2::ggplot(data, ggplot2::aes(year, value, colour = series)) +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::geom_text(ggplot2::aes(label = series), data = labels, hjust = 0, nudge_x = 0.3, size = 3,
                       colour = "#52514e", show.legend = FALSE) +
    ggplot2::scale_colour_manual(values = series_colours, name = NULL) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(mult = c(0.02, 0.16))) +
    ggplot2::scale_y_continuous(limits = c(0, NA), labels = \(v) format(v, big.mark = ",", trim = TRUE)) +
    ggplot2::labs(x = NULL, y = y_label) +
    theme_figures()
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  ggplot2::ggsave(path, figure, width = 7.5, height = 3.8, dpi = 200, bg = "white")
}

#' Draw one map per reporting year at 10 km, where each tile is the sum of 100 cells of 1 km.
#'
#' @param maps A SpatRaster with one layer per year, named `<prefix><year>`.
#' @param prefix Prefix of the layer names.
#' @param countries An sf table of the country boundaries.
#' @param legend_title Title of the colour scale.
#' @param path Output file.
map_figure <- function(maps, prefix, countries, legend_title, path) {
  map_data <- terra::aggregate(maps, fact = 10, fun = "sum", na.rm = TRUE) |>
    terra::as.data.frame(xy = TRUE) |>
    pivot_longer(starts_with(prefix), names_to = "year", values_to = "value") |>
    mutate(year = sub(prefix, "", year)) |>
    filter(value > 0)
  figure <- ggplot2::ggplot(map_data) +
    ggplot2::geom_tile(ggplot2::aes(x = x, y = y, fill = value)) +
    ggplot2::geom_sf(data = countries, fill = NA, linewidth = 0.1) +
    ggplot2::scale_fill_gradient(low = "#dbe9f8", high = "#0b3a75", transform = "sqrt", name = legend_title) +
    ggplot2::facet_wrap(~year, ncol = 3) +
    ggplot2::coord_sf(xlim = c(2.6e6, 6.6e6), ylim = c(1.4e6, 5.4e6), datum = NA) +
    ggplot2::theme_void() +
    ggplot2::labs(x = NULL, y = NULL)
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  ggplot2::ggsave(path, figure, width = 10, height = 7.2, dpi = 150, bg = "white")
}

#' Signed balance by land category, country and year.
#'
#' The inventory reports removals as negative values and emissions as positive values. The sign is
#' reversed so that uptake is positive. A category that is missing for a country is set to zero and
#' flagged in `gap`.
#'
#' @param env Table from `scripts/02_download_eurostat.R`.
#' @param categories Named vector of the CRF categories to keep (names are the codes).
#' @param geos Countries to keep.
#' @param years Years to keep.
#' @return Tibble with geo, year, src_crf, category, balance (uptake positive) and gap.
signed_balance <- function(env, categories, geos, years) {
  expand_grid(geo = geos, year = years, src_crf = names(categories)) |>
    left_join(
      env |> filter(src_crf %in% names(categories)) |> select(geo, year, src_crf, thousand_t_co2),
      by = c("geo", "year", "src_crf")
    ) |>
    mutate(
      gap = is.na(thousand_t_co2),
      balance = -replace(thousand_t_co2, is.na(thousand_t_co2), 0),
      category = unname(categories[src_crf])
    ) |>
    select(geo, year, src_crf, category, balance, gap)
}

#' Removals and emissions of each category from its signed balance.
#'
#' A positive balance is a removal and a negative one is an emission, so a category that is a net
#' source in a year counts as an emission in that year.
#'
#' @param balance Table from `signed_balance()`.
#' @return `balance` with `removals` and `emissions`, both non-negative.
split_removals_emissions <- function(balance) {
  balance |>
    mutate(removals = pmax(balance, 0), emissions = pmax(-balance, 0))
}

#' EU net flow and its allocation to countries.
#'
#' The offset is computed once for the EU. It is the total removals minus the total emissions over all
#' land categories and countries. The EU net is then shared among the countries in proportion to their
#' removals of forest land, as in Equation 6.1 of La Notte et al. (2021), so the national values add up to
#' the EU net. A negative EU net gives no flow. The table also holds the flow without the offset, which is
#' the total removals of the country, and the missed flow, which is the difference between the two.
#'
#' @param land Table from `split_removals_emissions()`, land categories only.
#' @return Tibble by geo and year with the forest removals, the national balance, the EU totals, the
#'   forest share, the actual flow, the flow without offset and the missed flow.
allocate_offset <- function(land) {
  land |>
    summarise(
      forest_removals = sum(removals[src_crf == "CRF4A"]),
      total_removals = sum(removals),
      total_emissions = sum(emissions),
      national_balance = sum(balance),
      .by = c(geo, year)
    ) |>
    mutate(
      eu_removals = sum(total_removals),
      eu_emissions = sum(total_emissions),
      eu_net = pmax(eu_removals - eu_emissions, 0),
      forest_share = forest_removals / sum(forest_removals),
      flow = eu_net * forest_share,
      flow_no_offset = total_removals,
      missed_flow = flow_no_offset - flow,
      .by = year
    )
}

#' Share each country's flow among the emitting sectors.
#'
#' @param flow Table from `allocate_offset()` with geo, year and flow.
#' @param env Table from `scripts/02_download_eurostat.R`.
#' @return Tibble by geo, year and sector with the sector emissions, its share of the total CO2
#'   emissions without LULUCF and the allocated flow.
allocate_to_sectors <- function(flow, env) {
  env |>
    inner_join(sector_groups, by = "src_crf") |>
    summarise(sector_emissions = sum(thousand_t_co2), .by = c(geo, year, sector)) |>
    mutate(share = sector_emissions / sum(sector_emissions), .by = c(geo, year)) |>
    inner_join(flow |> select(geo, year, flow), by = c("geo", "year")) |>
    mutate(allocated_flow = flow * share)
}
