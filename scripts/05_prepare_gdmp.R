# Prepare annual Gross Dry Matter Productivity (GDMP), the weight of the spatial key of the maps.
#
# Why    : the national flow is placed on forest in proportion to productivity, and the source is 36 global files a year.
# Source : Copernicus Land Monitoring Service, Gross Dry Matter Productivity, 10-daily, global,
#          read from the Copernicus Data Space Ecosystem S3 store (cloud optimised GeoTIFF).
#            v2 1 km, 1999 to 2020 (doi:10.2909/b54be6e3-5962-4e9a-a443-9ff7ea943dfe)  years 2000, 2006, 2012
#            v2 300 m, 2014 to present (doi:10.2909/fd838f95-21e9-4f37-a9b8-b438d9dc4edf)  years 2018, 2024
#          2018 is also read from the 1 km product to compare the two products.
# Access : Only needed when an annual file in refs/gdmp_annual/ is missing. It takes a free Copernicus Data Space
#          account with S3 keys (https://documentation.dataspace.copernicus.eu/APIs/S3.html), in the environment
#          variables CDSE_S3_ACCESS_KEY and CDSE_S3_SECRET_KEY. The keys are never written to a file.
# Method : Each 10-daily file holds a daily rate in kg dry matter per hectare per day. The annual value is the sum
#          of the 36 dekads, each multiplied by its number of days (10, 10 and the rest of the month).
#          Missing cells in a dekad count as zero. Only the part that covers Europe is read.
# Inputs : data/inputs/corine/CLC2018_forest_pct_1km.tif (script 04), for the comparison of the products.
# Outputs: refs/gdmp_annual/gdmp_<product>_<year>_4326.tif   annual sum at the native resolution, not versioned
#          data/inputs/gdmp/GDMP_<year>_1km.tif              annual sum on the 1 km EPSG:3035 grid of the maps
#                                                            (the 300 m product is averaged to 1 km)
#          refs/gdmp_comparison/GDMP_2018_1km_from_1km_product.tif, the other product of 2018, not versioned
#          data/outputs/report/gdmp_comparison.rds           comparison of the two products over forest in 2018
# Run    : source("scripts/05_prepare_gdmp.R", encoding = "UTF-8"), from the project root. Needs refs/, and it takes
#          a few hours if the annual files have to be read from the store. Resumable at the level of the year.

source("scripts/helpers_common.R", encoding = "UTF-8")

annual_dir <- "refs/gdmp_annual"
cache_dir <- "refs/gdmp_cache"
out_dir <- "data/inputs/gdmp"
comparison_file <- "refs/gdmp_comparison/GDMP_2018_1km_from_1km_product.tif"
for (d in c(annual_dir, cache_dir, out_dir, dirname(comparison_file))) dir.create(d, showWarnings = FALSE, recursive = TRUE)

catalogue_url <- "https://s3.waw3-1.cloudferro.com/swift/v1/CatalogueCSV/bio-geophysical/dry-gross_dry_matter_productivity/%s/%s_cog.csv"
s3_root <- "/vsis3/eodata/CLMS/bio-geophysical/dry-gross_dry_matter_productivity"
template <- grid_1km()
n_cores <- max(1L, min(4L, parallel::detectCores() - 1L))

# Years and products to build
jobs <- tibble::tribble(
  ~year, ~product,
  2000, "1km", 2006, "1km", 2012, "1km", 2018, "1km", 2018, "300m", 2024, "300m"
)

#' Set the access to the store for this process and the ones it starts.
use_s3_keys <- function() {
  access_key <- Sys.getenv("CDSE_S3_ACCESS_KEY")
  secret_key <- Sys.getenv("CDSE_S3_SECRET_KEY")
  stopifnot("Set CDSE_S3_ACCESS_KEY and CDSE_S3_SECRET_KEY" = nzchar(access_key) && nzchar(secret_key))
  Sys.setenv(
    AWS_ACCESS_KEY_ID = access_key, AWS_SECRET_ACCESS_KEY = secret_key,
    AWS_S3_ENDPOINT = "eodata.dataspace.copernicus.eu", AWS_VIRTUAL_HOSTING = "FALSE",
    AWS_HTTPS = "YES", AWS_DEFAULT_REGION = "default"
  )
}

#' Paths of the 36 dekads of a year, from the public catalogue of the product.
dekad_paths <- function(year, product) {
  dataset <- if (product == "1km") "gdmp_global_1km_10daily_v2" else "gdmp_global_300m_10daily_v2"
  cat_file <- file.path(cache_dir, paste0("catalogue_", dataset, ".csv"))
  if (!file.exists(cat_file)) {
    download.file(sprintf(catalogue_url, dataset, dataset), cat_file, quiet = TRUE, mode = "wb")
  }
  cat <- read.csv2(cat_file, stringsAsFactors = FALSE)
  cat <- cat[substr(cat$nominal_date, 1, 4) == as.character(year), ]
  # Use the most consolidated release (RT6) when several releases of a dekad exist
  if (any(grepl("-RT6_", cat$name))) cat <- cat[grepl("-RT6_|GDMP300-RT6_", cat$name), ]
  cat$date <- as.Date(substr(cat$nominal_date, 1, 10))
  cat <- cat[order(cat$date), ]
  stopifnot("A year needs 36 dekads" = nrow(cat) == 36L, !anyDuplicated(cat$date))

  folder <- cat$name
  # The raster inside the folder repeats the product name and inserts the layer name GDMP
  file <- sub("_cog$", ".tiff", sub("^(c_gls_GDMP300|c_gls_GDMP)", "\\1-GDMP", folder))
  tibble(
    date = cat$date,
    path = file.path(s3_root, dataset, format(cat$date, "%Y/%m/%d"), folder, file),
    days = as.integer(cat$date - c(as.Date(paste0(year - 1, "-12-31")), head(cat$date, -1)))
  )
}

#' Read one dekad, crop it to Europe and write it multiplied by its days.
read_dekad <- function(path, days, out_file) {
  if (file.exists(out_file)) return(out_file)
  r <- terra::crop(terra::rast(path), terra::ext(-32, 45, 27, 72))
  r <- terra::ifel(is.na(r), 0, r) * days
  terra::writeRaster(r, out_file, overwrite = TRUE, datatype = "FLT4S",
                     gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES"))
  out_file
}

for (i in seq_len(nrow(jobs))) {
  year <- jobs$year[i]
  product <- jobs$product[i]
  annual_file <- file.path(annual_dir, sprintf("gdmp_%s_%s_4326.tif", product, year))
  # The 1 km product for 2018 is kept apart for the comparison with the 300 m product
  out_file <- if (product == "1km" && year == 2018) comparison_file else file.path(out_dir, sprintf("GDMP_%s_1km.tif", year))

  if (!file.exists(annual_file)) {
    use_s3_keys()
    dekads <- dekad_paths(year, product)
    tmp <- file.path(cache_dir, sprintf("%s_%s", product, year))
    dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
    files <- file.path(tmp, format(dekads$date, "dekad_%Y%m%d.tif"))
    # Fresh R processes inherit the S3 settings from the environment variables set above
    cluster <- parallel::makeCluster(n_cores)
    parallel::parLapplyLB(cluster, seq_len(nrow(dekads)), function(k, paths, days, files, read_dekad) {
      read_dekad(paths[k], days[k], files[k])
    }, paths = dekads$path, days = dekads$days, files = files, read_dekad = read_dekad)
    parallel::stopCluster(cluster)
    stopifnot("Some dekads were not written" = all(file.exists(files)))
    total <- sum(rast(files))
    names(total) <- sprintf("gdmp_%s_%s", product, year)
    writeRaster(total, annual_file, overwrite = TRUE, datatype = "FLT4S",
                gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "TILED=YES"))
    unlink(tmp, recursive = TRUE)
  }

  if (!file.exists(out_file)) {
    annual <- rast(annual_file)
    method <- if (product == "300m") "average" else "bilinear"
    on_grid <- project(annual, template, method = method)
    writeRaster(on_grid, out_file, overwrite = TRUE, datatype = "FLT4S",
                gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3", "ZLEVEL=9", "TILED=YES"))
  }
}

# Compare the two products of 2018 over the cells that are mostly forest. The 1 km product stays in refs/, so
# this table is only written here, by a stage that has that file.
on_forest <- read_forest_share(2018) > 0.5
cells <- tibble(
  p300 = values(mask(rast(file.path(out_dir, "GDMP_2018_1km.tif")), on_forest, maskvalues = FALSE))[, 1],
  p1k = values(mask(rast(comparison_file), on_forest, maskvalues = FALSE))[, 1]
) |>
  filter(!is.na(p300), !is.na(p1k))

save_report_table(
  tibble(
    forest_cells = nrow(cells),
    pearson = cor(cells$p300, cells$p1k),
    spearman = cor(cells$p300, cells$p1k, method = "spearman"),
    mean_300m = mean(cells$p300),
    mean_1km = mean(cells$p1k),
    ratio_of_means = mean(cells$p300) / mean(cells$p1k)
  ),
  "gdmp_comparison"
)
