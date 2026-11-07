# Helper functions shared by the numbered scripts.
# Load with: source("scripts/helpers_common.R", encoding = "UTF-8")
# Each function does one small job so the scripts read as a sequence of short steps.
# Topic-specific helpers go in their own file, for example scripts/helpers_carbon.R.

library(dplyr)
library(terra)

# ---------------------------------------------------------------------------
# Grid and compact inputs
# ---------------------------------------------------------------------------

#' The 1 km grid of the maps, in EPSG:3035 and aligned with the Corine grid.
#'
#' @return An empty SpatRaster.
grid_1km <- function() {
  rast(xmin = 2636000, xmax = 7317000, ymin = 1385900, ymax = 5415900, resolution = 1000, crs = "EPSG:3035")
}

#' Read the share of each 1 km cell that is forest.
#'
#' The files hold whole percentages, which keeps them small. This function returns the same 32-bit values as
#' a share stored as a float, so always read the files through it, because a direct division gives values
#' that differ in the last digits and that would change the maps.
#'
#' @param year Year of the Corine accounting layer.
#' @return A SpatRaster with shares from 0 to 1.
read_forest_share <- function(year) {
  float_file <- tempfile(sprintf("forest_%s_", year), fileext = ".tif")
  writeRaster(
    rast(sprintf("data/inputs/corine/CLC%s_forest_pct_1km.tif", year)) / 100,
    float_file, datatype = "FLT4S", gdal = "COMPRESS=DEFLATE"
  )
  rast(float_file)
}

#' Read the NUTS regions of levels 0, 2 and 3 of the EU27 from the full boundary file in refs/.
#'
#' @return An sf table with level, nuts_id, name and geo.
read_nuts_regions <- function() {
  eu27 <- sf::st_read("data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0.gpkg", quiet = TRUE) |>
    filter(eu27) |>
    pull(geo)
  sf::st_read(
    "refs/INCA_plugin/src/inca/data/NUTS_RG_01M_2024_3035_LEVL0123_INCA.gpkg",
    layer = "NUTS_RG_01M_2024_3035.gpkg", quiet = TRUE
  ) |>
    filter(LEVL_CODE %in% c(0, 2, 3), substr(NUTS_ID, 1, 2) %in% eu27) |>
    transmute(level = paste0("NUTS", LEVL_CODE), nuts_id = NUTS_ID, name = NAME_LATN, geo = substr(NUTS_ID, 1, 2)) |>
    arrange(level, nuts_id)
}

# ---------------------------------------------------------------------------
# Spatial disaggregation
# ---------------------------------------------------------------------------

#' Rasterise the country polygons on the grid of a template raster.
#'
#' @param countries A SpatVector with a character column `geo`.
#' @param template A SpatRaster that defines the grid.
#' @return A list with `raster` (integer country ids per cell) and `ids` (a tibble
#'   that links each id to its country code).
make_country_ids <- function(countries, template) {
  countries$id <- seq_len(nrow(countries))
  grid <- rasterize(countries, template, field = "id")
  list(
    raster = grid,
    ids = tibble(id = countries$id, geo = countries$geo)
  )
}

#' Sum the weights of each country once, so every year can reuse the result.
#'
#' @param weight A SpatRaster of non-negative weights.
#' @param country_ids Output of `make_country_ids()`.
#' @return A tibble with geo and weight_sum.
country_weight_sums <- function(weight, country_ids) {
  zonal(weight, country_ids$raster, fun = "sum", na.rm = TRUE) |>
    setNames(c("id", "weight_sum")) |>
    left_join(country_ids$ids, by = "id") |>
    select(geo, weight_sum)
}

#' Spread country totals over a weight raster.
#'
#' Each cell receives `total * weight / weight_sum` for its country, so the cells of
#' a country add up to the national total (conservation of the sum).
#'
#' @param totals A tibble with geo and value (the national totals).
#' @param weight A SpatRaster of weights.
#' @param country_ids Output of `make_country_ids()`.
#' @param weight_sums Output of `country_weight_sums()`.
#' @return A SpatRaster with the same units as `totals$value`.
spread_totals <- function(totals, weight, country_ids, weight_sums) {
  per_weight <- country_ids$ids |>
    left_join(weight_sums, by = "geo") |>
    left_join(totals |> select(geo, value), by = "geo") |>
    mutate(factor = if_else(weight_sum > 0, value / weight_sum, NA_real_)) |>
    filter(!is.na(factor))

  factor_raster <- classify(
    country_ids$raster,
    rcl = as.matrix(per_weight[, c("id", "factor")]),
    others = NA
  )
  weight * factor_raster
}

# ---------------------------------------------------------------------------
# Export and checks
# ---------------------------------------------------------------------------

#' Save a long table that later scripts read.
#'
#' @param x A data frame.
#' @param name File name without extension.
#' @param dir Output directory.
save_table <- function(x, name, dir = "data/outputs/results") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  saveRDS(x, file.path(dir, paste0(name, ".rds")))
  invisible(x)
}

#' Save a small table that the report reads.
#'
#' @param x A data frame.
#' @param name File name without extension.
save_report_table <- function(x, name, dir = "data/outputs/report") {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  saveRDS(x, file.path(dir, paste0(name, ".rds")))
  invisible(x)
}

#' Run a check that stops the script on failure, and return a row for the report.
#'
#' @param a,b Numbers that should agree.
#' @param label Description of the check.
#' @param tolerance Largest gap allowed.
#' @param relative Whether the gap is relative to `b`. Use FALSE when `b` can be close to zero.
#' @return A one-row tibble with the check, its largest gap and its tolerance.
record_check <- function(a, b, label, tolerance = 1e-6, relative = TRUE) {
  gap <- abs(a - b)
  if (relative) gap <- gap / pmax(abs(b), 1e-9)
  largest <- max(gap, na.rm = TRUE)
  if (largest > tolerance) stop("Check failed: ", label, ". Largest gap ", largest, ", tolerance ", tolerance)
  tibble(check = label, largest_gap = largest, tolerance = tolerance, relative = relative)
}
