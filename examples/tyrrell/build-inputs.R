# Written by Codex

# Refresh the reviewed Tyrrell example inputs ----
# Maintainers only: run after stages 01 and 02, with Census network access.
# An optional first argument selects a directory containing those intermediates.

source("R/nc-utils.R")
source("R/check-inputs.R")
require_packages(c("checkmate", "digest", "dplyr", "sf", "tibble", "tigris"))
config <- read_pipeline_config()
args <- commandArgs(trailingOnly = TRUE)
intermediate_dir <- if (length(args)) args[[1]] else project_path(config$paths$intermediate)
example_dir <- project_path("examples", "tyrrell")
input_dir <- fs::path(example_dir, "inputs")
fs::dir_create(input_dir)
verify_inputs(project_path(config$manifests$inputs), project_path(config$paths$raw))

cli::cli_h1("Extract Tyrrell County example")
counts <- readr::read_rds(fs::path(intermediate_dir, "nc_vf_agg.rds")) |>
  dplyr::filter(.data$county == "37177") |>
  dplyr::select(county_name, county, vtd, race, party, n) |>
  dplyr::arrange(vtd, race, party)
covariates <- readr::read_rds(fs::path(intermediate_dir, "nc_bg_cov.rds")) |>
  dplyr::filter(substr(.data$GEOID, 1, 5) == "37177") |>
  dplyr::select(GEOID, pop, area, med_age, med_inc, edu_coll, edu_hsless,
                edu_prof, edu_somecoll, pop_dens, city_dist, white_pov)
block_groups <- tigris::block_groups("NC", county = "Tyrrell", year = config$tiger$year, progress_bar = FALSE) |>
  dplyr::select(GEOID) |>
  dplyr::left_join(covariates, by = "GEOID", relationship = "one-to-one") |>
  dplyr::arrange(GEOID)
precincts <- sf::read_sf(project_path(config$paths$raw, config$inputs$sbe_root)) |>
  dplyr::filter(.data$county_nam == "TYRRELL") |>
  dplyr::transmute(vtd = as.character(glue::glue("37177{prec_id}")), county_nam, fips = "37177") |>
  dplyr::arrange(vtd)
stopifnot(nrow(counts) > 0L, nrow(block_groups) == 5L, !anyNA(block_groups$pop),
          nrow(precincts) == 6L, setequal(counts$vtd, precincts$vtd))

readr::write_csv(counts, fs::path(input_dir, "voter-counts.csv"), na = "")
purrr::iwalk(list(`block-groups` = block_groups, precincts = precincts), function(data, name) {
  sf::st_write(sf::st_transform(data, 4326), fs::path(input_dir, glue::glue("{name}.geojson")),
               delete_dsn = TRUE, quiet = TRUE,
               layer_options = c("RFC7946=YES", "COORDINATE_PRECISION=7", "SIGNIFICANT_FIGURES=17"))
})

# The example has its own hashes; the full-build manifest is unchanged.
paths <- fs::path(input_dir, c("voter-counts.csv", "block-groups.geojson", "precincts.geojson"))
entries <- file_manifest(paths, root_dir = example_dir) |>
  dplyr::mutate(
    rows = c(nrow(counts), nrow(block_groups), nrow(precincts)),
    description = c("Tyrrell precinct-by-race-by-party registration counts; no individual records.",
                    "Five 2024 TIGER block groups with frozen ACS 2023 five-year covariates and distances.",
                    "Six unsimplified Tyrrell precinct boundaries from the 2025-02-25 SBE bundle."),
    role = c("Pivot the 16 joint cells and compute precinct race, party, and total margins.",
             "Match block groups to precincts by area and population-weight the final covariates.",
             "Define match targets and supply the final geometry with vtd, county_nam, and fips.")
  )
manifest <- list(
  schema_version = 1, algorithm = "sha256", dataset_id = "tyrrell_offline_example",
  roots = "inputs", pending_roots = list(), county = "37177",
  source_manifest = "manifests/inputs.yml",
  intermediate_source = as.character(fs::path_rel(fs::path_abs(intermediate_dir), start = project_root())),
  source_stages = c("prepare/01_nc-vf-fmt.R", "prepare/02_nc-acs_covs.R"),
  acs_year = config$acs$year, tiger_year = config$tiger$year,
  precinct_crs = 2264L, block_group_crs = 4269L, simplify_keep = config$geometry$simplify_keep,
  expected = list(precincts = nrow(precincts), voter_total = sum(counts$n), population = sum(covariates$pop)),
  files = purrr::transpose(entries)
)
write_yaml_file(manifest, project_path("manifests", "example-tyrrell.yml"))
cli::cli_alert_success("Extracted {scales::comma(sum(entries$bytes))} bytes; review data and hash changes before committing.")
