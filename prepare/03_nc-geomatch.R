# Written by Codex

# Spatial match to SBE precincts ----
# Outputs: nc_vtd_cov.rds and nc_vtd_geo.rds in data/intermediate.

source("R/nc-utils.R")
source("R/check-inputs.R")
source("R/nc-reference.R")
source("R/nc-precinct-recodes.R")
source("R/nc-geomatch.R")

require_packages(c("dplyr", "geomander", "rmapshaper", "sf", "stringr", "tibble", "tigris"))

config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 03: geometry match")
input_manifest <- project_path(config$manifests$inputs)
require_manifest_roots(input_manifest, config$inputs$sbe_root)

cov_path <- project_path(config$paths$intermediate, "nc_bg_cov.rds")
if (!file.exists(cov_path)) {
  cli::cli_abort("Run stage 02 before geomatching: {.file {cov_path}} is missing.")
}

sbe_path <- project_path(config$paths$raw, config$inputs$sbe_root)
county_geometry_ref <- nc_county_geometry_reference()
geometry_edits <- haywood_gaston_geometry_edits()

precinct_geo_raw <- sf::read_sf(sbe_path)
precinct_geo <- precinct_geo_raw |>
  dplyr::select(-dplyr::starts_with("Shape_Leng"), -dplyr::any_of("of_prec_id")) |>
  dplyr::left_join(
    geometry_edits,
    by = c("county_nam", "enr_desc"),
    relationship = "many-to-one"
  ) |>
  dplyr::mutate(
    prec_id = dplyr::coalesce(.data$prec_id_recode, .data$prec_id),
    prec_id_wake = dplyr::if_else(.data$county_nam == "WAKE", stringr::word(.data$prec_id, 1L, sep = "-"), NA_character_),
    prec_id = dplyr::coalesce(.data$prec_id_wake, .data$prec_id)
  ) |>
  dplyr::select(-dplyr::any_of(c("prec_id_recode", "prec_id_wake"))) |>
  dplyr::left_join(county_geometry_ref, by = "county_nam", relationship = "many-to-one") |>
  dplyr::mutate(vtd = stringr::str_c(.data$fips, .data$prec_id), .after = "enr_desc")

cli::cli_alert_info(
  "Matching {config$tiger$year} full block groups to {scales::comma(nrow(precinct_geo))} SBE geometry rows."
)
options(tigris_use_cache = TRUE)
acs_geo <- tigris::block_groups(config$state, year = config$tiger$year)
crosswalk <- block_group_crosswalk(acs_geo, precinct_geo)

coverage <- tibble::tibble(
  metric = c("block_groups", "sbe_rows", "sbe_distinct_vtd", "matched_distinct_vtd"),
  value = c(
    nrow(acs_geo),
    nrow(precinct_geo),
    dplyr::n_distinct(precinct_geo$vtd),
    dplyr::n_distinct(crosswalk$vtd)
  )
)
write_join_diagnostic(coverage, project_path(config$paths$diagnostics, "stage03_match_coverage.rds"))

bg_cov <- readr::read_rds(cov_path)
vtd_cov <- aggregate_precinct_covariates(bg_cov, crosswalk)

vtd_geo <- precinct_geo |>
  dplyr::select(vtd, fips, county_nam) |>
  rmapshaper::ms_simplify(keep = config$geometry$simplify_keep, keep_shapes = TRUE)

write_stage_rds(vtd_cov, project_path(config$paths$intermediate, "nc_vtd_cov.rds"))
write_stage_rds(vtd_geo, project_path(config$paths$intermediate, "nc_vtd_geo.rds"))
cli::cli_alert_success(
  "Built covariates for {scales::comma(nrow(vtd_cov))} precinct keys and geometry with {scales::comma(nrow(vtd_geo))} rows."
)
