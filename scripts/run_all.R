# Run the pipeline, or some of its stages, in order.
#
# Stages : inputs    scripts 01 to 07. Needs internet access and the files in refs/. A new release of the Eurostat
#                    data changes the results, so run it deliberately.
#          tables    scripts 08 and 09. Takes under a minute.
#          maps_1km  script 10. Takes a few minutes.
#          maps_100m scripts 11 and 12. Needs the files in refs/, and takes about four hours.
# Run    : from the project root, with the stages to run. With no stage named, it runs tables and maps_1km,
#          which need only the repository.
#            Rscript scripts/run_all.R
#            Rscript scripts/run_all.R tables
#            Rscript scripts/run_all.R inputs tables maps_1km maps_100m
#          The report is rendered afterwards with `quarto render`.

pipeline <- list(
  inputs = c("01_prepare_nuts", "02_download_eurostat", "03_download_hicp", "04_prepare_clc", "05_prepare_gdmp",
             "06_prepare_nuts_weights", "07_prepare_carbon_price"),
  tables = c("08_build_physical_accounts", "09_build_monetary_accounts"),
  maps_1km = "10_write_maps_1km",
  maps_100m = c("11_write_maps_100m", "12_check_maps_100m")
)

requested <- commandArgs(trailingOnly = TRUE)
if (length(requested) == 0) requested <- c("tables", "maps_1km")
unknown <- setdiff(requested, names(pipeline))
if (length(unknown) > 0) stop("Unknown stage: ", paste(unknown, collapse = ", "))

# Stages always run in the order of the pipeline, each script in its own environment.
for (stage in intersect(names(pipeline), requested)) {
  for (script in pipeline[[stage]]) {
    message("== ", script, ", ", format(Sys.time()))
    source(sprintf("scripts/%s.R", script), encoding = "UTF-8", local = new.env())
  }
}
