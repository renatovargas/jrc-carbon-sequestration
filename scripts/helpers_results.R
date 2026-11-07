# Helper functions for the results workbook of the carbon sequestration service, used by script 09.
# Load with: source("scripts/helpers_results.R", encoding = "UTF-8")
#
# The workbook has a Readme sheet, then one sheet per output table and NUTS level, each with a banner, a
# nested header and a total row. It needs scripts/helpers_carbon.R for `co2_to_c`.
library(dplyr)
library(tidyr)
library(openxlsx2)

results_number_format <- "#,##0.0"

# The tables of the workbook, each with the columns that it shows and their labels.
result_tables <- list(
  Flow_phys = list(
    title = "Actual flow of carbon sequestration with offset in physical terms (thousand tonnes)",
    metrics = c(flow = "CO2", flow_c = "Carbon")
  ),
  NoOffset_phys = list(
    title = "Flow of carbon sequestration without offset in physical terms (thousand tonnes)",
    metrics = c(flow_no_offset = "CO2", flow_no_offset_c = "Carbon")
  ),
  Missed_phys = list(
    title = "Missed flow of carbon sequestration in physical terms (thousand tonnes)",
    metrics = c(missed_flow = "CO2", missed_flow_c = "Carbon")
  ),
  Flow_mon = list(
    title = "Actual flow of carbon sequestration with offset in monetary terms (million euro)",
    metrics = c(flow_nominal = "Current prices", flow_constant = "Constant prices")
  ),
  Missed_mon = list(
    title = "Missed flow of carbon sequestration in monetary terms (million euro)",
    metrics = c(missed_nominal = "Current prices", missed_constant = "Constant prices")
  )
)

#' Write one results sheet.
#'
#' @param wb A workbook.
#' @param sheet Sheet name.
#' @param title Table title (second banner line).
#' @param note Explanatory text (third banner line).
#' @param data Long table with `nuts_id`, `name`, `year` and the metric columns.
#' @param metrics Named character vector, column name = header label.
#' @return The workbook.
write_results_sheet <- function(wb, sheet, title, note, data, metrics) {
  years <- sort(unique(data$year))
  wide <- data |>
    select(nuts_id, name, year, all_of(names(metrics))) |>
    pivot_wider(
      names_from = year, values_from = all_of(names(metrics)),
      names_glue = "{year}__{.value}", names_vary = "slowest"
    ) |>
    arrange(nuts_id)
  total <- wide |>
    summarise(across(-c(nuts_id, name), \(v) sum(v, na.rm = TRUE))) |>
    mutate(nuts_id = "EU27", name = "Total", .before = 1)
  wide <- bind_rows(wide, total)

  n_cols <- ncol(wide)
  n_met <- length(metrics)
  header_row <- 5L
  data_start <- 7L
  data_end <- data_start + nrow(wide) - 1L

  wb <- wb_add_worksheet(wb, sheet)

  banner <- c("Carbon sequestration accounts", title, note)
  for (i in 1:3) {
    wb <- wb_add_data(wb, sheet, x = banner[i], start_row = i, start_col = 1, col_names = FALSE)
    wb <- wb_merge_cells(wb, sheet, dims = wb_dims(rows = i, cols = 1:min(n_cols, 10)))
    wb <- wb_add_cell_style(
      wb, sheet, dims = wb_dims(rows = i, cols = 1),
      wrap_text = TRUE, vertical = "center"
    )
  }
  wb <- wb_set_row_heights(wb, sheet, rows = 1:3, heights = c(18, 18, 32))

  year_row <- c("Code", "Region", rep(as.character(years), each = n_met))
  metric_row <- c("Code", "Region", rep(unname(metrics), times = length(years)))
  wb <- wb_add_data(wb, sheet, x = matrix(year_row, nrow = 1),
                    start_row = header_row, start_col = 1, col_names = FALSE)
  wb <- wb_add_data(wb, sheet, x = matrix(metric_row, nrow = 1),
                    start_row = header_row + 1L, start_col = 1, col_names = FALSE)
  wb <- wb_merge_cells(wb, sheet, dims = wb_dims(rows = header_row:(header_row + 1L), cols = 1))
  wb <- wb_merge_cells(wb, sheet, dims = wb_dims(rows = header_row:(header_row + 1L), cols = 2))
  if (n_met > 1) {
    for (k in seq_along(years)) {
      first <- 3L + (k - 1L) * n_met
      wb <- wb_merge_cells(wb, sheet, dims = wb_dims(rows = header_row, cols = first:(first + n_met - 1L)))
    }
  }
  header_dims <- wb_dims(rows = header_row:(header_row + 1L), cols = 1:n_cols)
  wb <- wb_add_font(wb, sheet, dims = header_dims, bold = TRUE)
  wb <- wb_add_cell_style(wb, sheet, dims = header_dims,
                          wrap_text = TRUE, horizontal = "center", vertical = "center")
  wb <- wb_add_border(wb, sheet, dims = wb_dims(rows = header_row + 1L, cols = 1:n_cols),
                      bottom_border = "thin", top_border = "none",
                      left_border = "none", right_border = "none")
  wb <- wb_set_row_heights(wb, sheet, rows = header_row:(header_row + 1L), heights = c(20, 34))

  wb <- wb_add_data(wb, sheet, x = wide, start_row = data_start, start_col = 1,
                    col_names = FALSE, na = "", apply_cell_style = FALSE)
  wb <- wb_add_numfmt(wb, sheet, dims = wb_dims(rows = data_start:data_end, cols = 3:n_cols),
                      numfmt = results_number_format)
  total_dims <- wb_dims(rows = data_end, cols = 1:n_cols)
  wb <- wb_add_font(wb, sheet, dims = total_dims, bold = TRUE)
  wb <- wb_add_border(wb, sheet, dims = total_dims,
                      top_border = "thin", bottom_border = "thin",
                      left_border = "none", right_border = "none")
  wb <- wb_set_col_widths(wb, sheet, cols = 1:n_cols, widths = c(10, 30, rep(15, n_cols - 2L)))
  wb_freeze_pane(wb, sheet, first_active_row = data_start, first_active_col = 3L)
}

#' Regional values from national values, by land type.
#'
#' The removals of each land type of a country are shared among its NUTS regions in proportion to
#' the share of the region in the area of that type (the weighted area for forest). The sum over land
#' types is the flow without offset of the region. The actual flow is shared by the forest share.
#' Missed flow is the regional flow without offset minus the regional actual flow.
#'
#' @param national Table by `geo` and `year` with `flow`, one column per land type named
#'   `rem_<land_type>` (thousand tonnes of CO2) and `epoch`.
#' @param type_weights Table from `scripts/06_prepare_nuts_weights.R`.
#' @return Table with `level`, `nuts_id`, `name`, `geo`, `year`, `flow`, `flow_no_offset`, `missed_flow`.
regional_carbon_flows <- function(national, type_weights) {
  rem_cols <- grep("^rem_", names(national), value = TRUE)
  removals_long <- national |>
    select(geo, year, epoch, all_of(rem_cols)) |>
    pivot_longer(all_of(rem_cols), names_to = "land_type", names_prefix = "rem_", values_to = "removals")

  no_offset <- type_weights |>
    inner_join(removals_long, by = c("geo", "epoch", "land_type"), relationship = "many-to-many") |>
    summarise(flow_no_offset = sum(removals * share), .by = c(level, nuts_id, name, geo, year))

  actual <- type_weights |>
    filter(land_type == "forest") |>
    inner_join(national |> select(geo, year, epoch, flow), by = c("geo", "epoch"), relationship = "many-to-many") |>
    transmute(level, nuts_id, name, geo, year, flow = flow * share)

  no_offset |>
    inner_join(actual, by = c("level", "nuts_id", "name", "geo", "year")) |>
    mutate(missed_flow = flow_no_offset - flow)
}

#' Physical and monetary values of every region of the reporting years.
#'
#' @param national Table by `geo` and `year` with `flow`, `flow_no_offset`, `missed_flow`,
#'   `rem_<land_type>` columns, `price` (euro per tonne of CO2, current prices) and `deflator`.
#' @param type_weights Table from `scripts/06_prepare_nuts_weights.R`.
#' @param years Reporting years.
#' @param epochs Named integer vector that links each reporting year to a CLC epoch.
#' @return Table by region and year with the columns that the workbook shows.
regional_results <- function(national, type_weights, years, epochs) {
  national <- national |>
    filter(year %in% years) |>
    mutate(epoch = unname(epochs[as.character(year)]))

  regional_carbon_flows(national, type_weights) |>
    left_join(national |> select(geo, year, price, deflator), by = c("geo", "year")) |>
    mutate(
      flow_c = flow * co2_to_c,
      flow_no_offset_c = flow_no_offset * co2_to_c,
      missed_flow_c = missed_flow * co2_to_c,
      flow_nominal = flow * price / 1000, flow_constant = flow_nominal * deflator,
      missed_nominal = missed_flow * price / 1000, missed_constant = missed_nominal * deflator
    ) |>
    select(level, nuts_id, name, geo, year, flow, flow_c, flow_no_offset, flow_no_offset_c, missed_flow, missed_flow_c,
           flow_nominal, flow_constant, missed_nominal, missed_constant)
}

#' Compare the regional totals with the national totals.
#'
#' @param regional Table from `regional_results()`.
#' @param tables List of tables, each with a `metrics` vector (column = label).
#' @param tolerance Largest accepted absolute difference.
#' @return One row per table, metric, year and level (NUTS2, NUTS3).
results_checks <- function(regional, tables = result_tables, tolerance = 1e-6) {
  totals <- regional |>
    pivot_longer(-c(level, nuts_id, name, geo, year), names_to = "column") |>
    summarise(total = sum(value, na.rm = TRUE), .by = c(level, year, column)) |>
    pivot_wider(names_from = level, values_from = total)

  purrr::imap(tables, \(tab, nm) {
    tibble(table = nm, column = names(tab$metrics), metric = unname(tab$metrics))
  }) |>
    bind_rows() |>
    inner_join(totals, by = "column", relationship = "many-to-many") |>
    pivot_longer(c(NUTS2, NUTS3), names_to = "level", values_to = "regional_total") |>
    transmute(
      table, metric, year, level,
      national_total = NUTS0,
      regional_total,
      difference = regional_total - national_total,
      match = abs(difference) <= tolerance * pmax(1, abs(national_total))
    ) |>
    arrange(table, metric, level, year)
}

#' Build the results workbook of the carbon sequestration service.
#'
#' Sheets exist for the actual flow, the flow without offset and the missed flow in physical terms,
#' and for the actual flow and the missed flow in monetary terms, each for NUTS0, NUTS2 and NUTS3. A
#' national balance sheet and a checks sheet are added.
#'
#' @param national Table by `geo` and `year` with `removals`, `emissions` and `balance`.
#' @param regional Table from `regional_results()`.
#' @param checks Table from `results_checks()`.
#' @param type_weights Table from `scripts/06_prepare_nuts_weights.R`.
#' @param years Reporting years.
#' @param base_year Base year of the constant prices.
#' @param path Output file.
#' @return The path, invisibly.
write_carbon_results_workbook <- function(national, regional, checks, type_weights, years, base_year, path) {
  national <- national |> filter(year %in% years)

  readme <- c(
    "Carbon sequestration ecosystem service accounts, global climate regulation",
    paste0("Reporting years ", paste(years, collapse = ", "), ". Constant prices use ", base_year,
           " as the base year (Eurostat HICP, EU-27)."),
    "Sheets are named Flow, NoOffset or Missed, then phys or mon, then the NUTS level (NUTS0, NUTS2, NUTS3). The Balance_NUTS0 sheet reports national removals, emissions and the signed balance.",
    "Flow without offset is the total CO2 removals of forest land, cropland, grassland, wetlands, settlements and other land.",
    "Actual flow is the EU total removals minus the EU total emissions of the same land categories, attributed to countries in proportion to their removals of forest land.",
    "Missed flow is the flow without offset minus the actual flow, which is the part of the removals that compensates the emissions of land use.",
    "National values come from the greenhouse gas inventories in Eurostat dataset env_air_gge (CO2, thousand tonnes). Carbon is CO2 times 12/44.",
    "NUTS2 and NUTS3 values share the removals of each land type in proportion to the area of the land type in each region, and the actual flow in proportion to the forest weight of each region, so regions add up to the country.",
    "Monetary values are the CO2 values times the social cost of carbon in euro per tonne, in million euro.",
    "The Checks sheet compares the NUTS2 and NUTS3 totals with the NUTS0 total for every table, metric and year.",
    "The 100 m maps of the flow without offset and of the actual flow in physical and monetary terms are distributed separately."
  )

  wb <- wb_workbook() |>
    wb_add_worksheet("Readme") |>
    wb_add_data("Readme", x = readme, col_names = FALSE)
  wb <- wb_add_cell_style(wb, "Readme", dims = wb_dims(rows = seq_along(readme), cols = 1),
                          wrap_text = TRUE, vertical = "top")
  wb <- wb_set_col_widths(wb, "Readme", cols = 1, widths = 110)

  for (nm in names(result_tables)) {
    for (lv in c("NUTS0", "NUTS2", "NUTS3")) {
      wb <- write_results_sheet(
        wb,
        sheet = paste(nm, lv, sep = "_"),
        title = result_tables[[nm]]$title,
        note = paste0("Level ", lv, ". Reporting years ", paste(years, collapse = ", "),
                      ". Constant prices use ", base_year, " as the base year."),
        data = regional |> filter(level == lv),
        metrics = result_tables[[nm]]$metrics
      )
    }
  }

  country_names <- type_weights |> filter(level == "NUTS0") |> distinct(nuts_id, name, geo)
  balance <- country_names |> inner_join(national, by = "geo")
  wb <- write_results_sheet(
    wb, sheet = "Balance_NUTS0",
    title = "Removals, emissions and signed balance of land use in physical terms (thousand tonnes of CO2)",
    note = paste0("National values. Reporting years ", paste(years, collapse = ", "),
                  ". The balance is removals minus emissions."),
    data = balance,
    metrics = c(removals = "Removals", emissions = "Emissions", balance = "Balance")
  )

  wb <- wb_add_worksheet(wb, "Checks")
  wb <- wb_add_data(wb, "Checks", x = checks)
  wb <- wb_add_font(wb, "Checks", dims = wb_dims(rows = 1, cols = seq_along(checks)), bold = TRUE)
  wb <- wb_add_numfmt(wb, "Checks", dims = wb_dims(rows = 2:(nrow(checks) + 1L), cols = 5:7),
                      numfmt = "#,##0.000")
  wb <- wb_set_col_widths(wb, "Checks", cols = seq_along(checks), widths = c(14, 34, 8, 10, 16, 16, 16, 8))
  wb <- wb_freeze_pane(wb, "Checks", first_active_row = 2L)

  wb_save(wb, path)
  invisible(path)
}
