# Prepare the share of each NUTS2 and NUTS3 region in the weight of each land type of its country.
#
# Why    : the regional tables share the national values with these weights, and they need the boundaries of the
#          regions.
# Inputs : data/inputs/corine/clc_ecosystem_area_by_nuts.rds (script 04)
#          data/inputs/corine/CLC<year>_forest_pct_1km.tif (script 04)
#          data/inputs/gdmp/GDMP_<year>_1km.tif (script 05)
#          data/inputs/gis/NUTS_RG_01M_2024_3035_LEVL0123_INCA.gpkg (NUTS 2024 boundaries)
# Output : data/inputs/corine/clc_type_weight_by_nuts.rds
#            One row per EU27 region of levels 0, 2 and 3, year and land type, with the weight and its share
#            of the country total. Countries take share 1. The weight of forest is the sum over the region of
#            the forest share of each 1 km cell times its annual gross dry matter productivity, the weight of
#            the other land types is their area in hectares. When a country has no weight of a land type, the
#            share of the region in the total mapped land area of the country is used instead, and `fallback`
#            is TRUE.
# Run    : source("scripts/06_prepare_nuts_weights.R", encoding = "UTF-8"), from the project root.

source("scripts/helpers_common.R", encoding = "UTF-8")
library(sf)

area <- readRDS("data/inputs/corine/clc_ecosystem_area_by_nuts.rds")
years <- sort(unique(area$epoch))
regions <- read_nuts_regions()

# Forest weight of each region and year: forest share times productivity of the same year
forest_weight <- bind_rows(lapply(years, \(year) {
  weight <- read_forest_share(year) * rast(sprintf("data/inputs/gdmp/GDMP_%s_1km.tif", year))
  sums <- extract(weight, vect(regions), fun = sum, na.rm = TRUE, ID = FALSE)
  regions |>
    st_drop_geometry() |>
    transmute(epoch = as.integer(year), level, nuts_id, name, geo, land_type = "forest",
              hectares = replace(sums[[1]], is.na(sums[[1]]), 0))
}))

# The fallback share rests on land area, so this total comes before forest area gives way to the forest weight.
total_area <- area |>
  summarise(total_ha = sum(hectares), .by = c(epoch, level, nuts_id, geo))

type_weights <- bind_rows(area |> filter(land_type != "forest"), forest_weight) |>
  transmute(epoch, level, nuts_id, name, geo, land_type, weight_sum = hectares) |>
  left_join(total_area, by = c("epoch", "level", "nuts_id", "geo")) |>
  group_by(epoch, level, geo, land_type) |>
  mutate(
    fallback = level != "NUTS0" & sum(weight_sum) <= 0,
    share = case_when(
      level == "NUTS0" ~ 1,
      sum(weight_sum) > 0 ~ weight_sum / sum(weight_sum),
      sum(total_ha) > 0 ~ total_ha / sum(total_ha),
      .default = NA_real_
    )
  ) |>
  ungroup() |>
  select(-total_ha) |>
  arrange(epoch, level, nuts_id, land_type)

saveRDS(type_weights, "data/inputs/corine/clc_type_weight_by_nuts.rds")
