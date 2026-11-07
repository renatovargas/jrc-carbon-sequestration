# Repository structure and conventions

This file describes how the repository is organised and which conventions the documents follow. The
rules in `AGENTS.md` still apply. This file only adds what those rules do not cover.

## Layout

```
.
├── AGENTS.md                 rules for authors
├── structure.md              this file
├── _quarto.yml               project, menu and format configuration
├── index.qmd                 home page, a short description of what the site is about
├── styles.css                site styles (almost empty)
├── assets/
│   └── apa-6th-edition.csl   citation style shared by all documents
├── documentation/
│   ├── index.qmd             list of the reports, one definition per report
│   └── methods/
│       └── carbon-sequestration/
│           ├── index.qmd     the report
│           └── carbon-sequestration.bib
├── downloads/
│   └── index.qmd             buttons to the results workbook and the 100 m maps, HTML only
├── scripts/
│   ├── run_all.R             runs the pipeline, or some of its stages, in order
│   ├── NN_<verb>_<object>.R  numbered scripts of the pipeline
│   ├── helpers_common.R      grid, spatial disaggregation, export and check functions
│   ├── helpers_carbon.R      method of the physical accounts and figures
│   ├── helpers_monetary.R    deflator
│   ├── helpers_results.R     results by region and workbook layout
│   └── helpers_report.R      reads the small tables and formats them, for the report only
├── data/
│   ├── inputs/
│   │   ├── gis/              NUTS boundaries, as distributed and for the countries
│   │   ├── eurostat/         CO2 inventory and price index
│   │   ├── prices/           carbon price
│   │   ├── corine/           forest share at 1 km, as whole percentages, and land type tables by region
│   │   └── gdmp/             annual productivity at 1 km
│   └── outputs/
│       ├── results/          long tables (rds) and the results workbook (xlsx)
│       ├── report/           small tables that the scripts write for the report (rds)
│       └── figures/          figures that the scripts write for the report (png)
├── research/                 notes, not published
├── refs/                     downloads, reference files and maps, not versioned
│   ├── clc_accounting/       Corine accounting layers at 100 m
│   ├── clc_1km_cache/        shares of all land types at 1 km, written by 04
│   ├── gdmp_annual/          annual productivity at native resolution, written by 05
│   ├── gdmp_comparison/      the other productivity product of 2018 on the 1 km grid, written by 05
│   ├── maps_1km/             1 km maps (GeoTIFF), written by 10
│   └── maps_100m/            100 m maps (GeoTIFF), written by 11, published outside the repository
└── docs/                     rendered site, generated, do not edit
```

## Reproducibility levels

The repository supports two levels. The first level needs only the repository. The stages `tables` and `maps_1km`
of `scripts/run_all.R` read the compact products in `data/inputs/`, rebuild every table and write the 1 km maps to
`refs/maps_1km/`, and the report renders from the small tables with no further step. The second level rebuilds
the compact inputs and the 100 m maps, and it needs the sources in `refs/` and internet access.

## Scripts

Scripts run in the order of their numbers, from the project root. `scripts/run_all.R` runs them by stage, namely `inputs`, `tables`, `maps_1km` and `maps_100m`, and with no stage named it runs `tables` and `maps_1km`. Scripts 04 and 05 skip outputs that already exist, and so does script 11.

All calculation is in the scripts, and the report reads their small tables and figures. After a change, rerun only what it affects, and then render:

| Change | Rerun |
|----|----|
| Text or formatting of the report | Only `quarto render` |
| The inventory or the physical method | `08`, `09`, `10` |
| The price or the deflator | `07`, `09`, `10` |
| The forest share or the productivity | `06`, `08`, `09`, `10` |
| Any of the above that changes the maps | Also delete the files in `refs/maps_100m/`, and run `11` and `12` |

| Script | Purpose |
|----|----|
| `01_prepare_nuts.R` | Country boundaries |
| `02_download_eurostat.R` | CO2 inventory by source sector |
| `03_download_hicp.R` | Consumer price index |
| `04_prepare_clc.R` | Forest share at 1 km and land type areas by region |
| `05_prepare_gdmp.R` | Annual productivity at 1 km, and the comparison of the two products of 2018 |
| `06_prepare_nuts_weights.R` | Share of each region in the weight of each land type |
| `07_prepare_carbon_price.R` | Carbon price series |
| `08_build_physical_accounts.R` | Removals, emissions, actual flow, missed flow and sector allocation, with their checks |
| `09_build_monetary_accounts.R` | Value of the flows, regional results and the workbook, with their checks |
| `10_write_maps_1km.R` | 1 km maps, map figures and comparison of maps with tables |
| `11_write_maps_100m.R` | 100 m maps |
| `12_check_maps_100m.R` | Comparison of the 100 m maps with the tables |

## Menu

The site has three entries in the top bar, "Home", "Documents" and "Downloads". A new report needs its folder under
`documentation/methods/`, a line in the sidebar of `_quarto.yml` and a definition in
`documentation/index.qmd`.

## Report

The report is a narrative with no visible code, and it has these sections, in this order: Summary, Introduction, Methods,
Results, Limitations, References and Annex I. Methods follows the logical order of the scripts, with substeps inside each, and it
explains why each decision was taken. Results follows the products. Only the report has a PDF version, which it declares
in its own `format`, so `_quarto.yml` sets HTML alone.

- Every step of the method links in the text to the entry of its script in Annex I, written as "see name.R in Annex I".
- Numbers in the text come from `data/outputs/report/` through inline code.
- Chunks only read a small table and show it, and their labels are lowercase words separated by hyphens.
- Callouts use `callout-note` for context and `callout-important` for anything that changes how the results should be read.
- The bibliography is one `.bib` file in the report folder, and the citation style is referenced as `../../../assets/apa-6th-edition.csl`.

## Data and file names

- Maps are named `carbon_<quantity>_gdmp_<resolution>_<year>.tif`.
- Long tables are `.rds` in `data/outputs/results/`. The only published table is the workbook `carbon_sequestration_results.xlsx`. CSV is kept only for short files edited or read by hand.
- The forest share in `data/inputs/corine/` is stored as whole percentages. `read_forest_share()` returns the original 32-bit values, so always read the files through that function, because a direct division changes the last digits and the maps with them.
- Maps are written as 32-bit floats with `COMPRESS=DEFLATE`, `PREDICTOR=3` and `TILED=YES`.
- All maps use EPSG:3035 (ETRS89 Lambert azimuthal equal-area), on a grid aligned with the Corine grid.
- Country codes follow Eurostat (`EL` for Greece, `EU27_2020` for the aggregate).

## Research notes

Notes in `research/` are plain markdown files with statements, each with its source, page and a verification
level (verified in text, inferred or verified online). They are not published.
