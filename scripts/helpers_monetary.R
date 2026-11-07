# Helper functions of the monetary accounts, used by scripts/09_build_monetary_accounts.R
# Load with: source("scripts/helpers_monetary.R", encoding = "UTF-8")

library(dplyr)

#' Rebase an index so that `base_year` equals 1 and return a deflator table.
#'
#' Real value (prices of `base_year`) = nominal value * deflator.
#'
#' @param hicp Tibble with year and an index column.
#' @param index_col Name of the index column.
#' @param base_year Reference year for constant prices.
#' @return Tibble with year and `deflator`.
make_deflator <- function(hicp, index_col, base_year) {
  base_value <- hicp[[index_col]][hicp$year == base_year]
  stopifnot(length(base_value) == 1)
  tibble(year = hicp$year, deflator = base_value / hicp[[index_col]])
}
