# Written by Codex

# Combine wide dataset ----
# Publishes the wide RDS, geometry RDS, and geometry GeoJSON.

source("R/nc-utils.R")
source("R/nc-reference.R")
source("R/nc-precinct-recodes.R")

require_packages(c("cli", "dplyr", "glue", "readr", "scales", "sf", "tibble", "tidyr", "yaml"))

config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 04: combine")

vf_path <- project_path(config$paths$intermediate, "nc_vf_agg.rds")
cov_path <- project_path(config$paths$intermediate, "nc_vtd_cov.rds")
geo_path <- project_path(config$paths$intermediate, "nc_vtd_geo.rds")
missing_stage_files <- c(vf_path, cov_path, geo_path)[!file.exists(c(vf_path, cov_path, geo_path))]
if (length(missing_stage_files) > 0L) {
  cli::cli_abort(c(
    "Required intermediate files are missing.",
    "x" = "{.file {missing_stage_files}}"
  ))
}

voter_counts <- readr::read_rds(vf_path)
precinct_covariates <- readr::read_rds(cov_path)
county_regions <- nc_regions_4()
joint_cells <- nc_joint_cell_names()

counts_factored <- voter_counts |>
  dplyr::mutate(
    race = factor(.data$race, levels = nc_race_levels()),
    party = factor(.data$party, levels = nc_party_levels())
  )
counts_wide <- counts_factored |>
  tidyr::pivot_wider(
    id_cols = c(county_name, county, vtd),
    names_from = c(race, party),
    values_from = n,
    names_expand = TRUE,
    values_fill = 0
  ) |>
  dplyr::select(county_name, county, vtd, dplyr::all_of(joint_cells))

wide_margins <- counts_wide |>
  dplyr::rowwise() |>
  dplyr::mutate(
    total = sum(dplyr::c_across(dplyr::all_of(joint_cells))),
    white_ = sum(dplyr::c_across(dplyr::starts_with("white_"))),
    black_ = sum(dplyr::c_across(dplyr::starts_with("black_"))),
    hisp_ = sum(dplyr::c_across(dplyr::starts_with("hisp_"))),
    other_ = sum(dplyr::c_across(dplyr::starts_with("other_"))),
    `_rep` = sum(dplyr::c_across(dplyr::ends_with("_rep"))),
    `_dem` = sum(dplyr::c_across(dplyr::ends_with("_dem"))),
    `_ind` = sum(dplyr::c_across(dplyr::ends_with("_ind"))),
    `_lib` = sum(dplyr::c_across(dplyr::ends_with("_lib"))),
    .after = vtd
  ) |>
  dplyr::ungroup()

missing_covariates <- sum(!wide_margins$vtd %in% precinct_covariates$vtd)
missing_regions <- sum(!wide_margins$county %in% county_regions$county)
if (missing_regions > 0L) {
  cli::cli_abort("Every county in the voter counts needs a region mapping.")
}
if (missing_covariates > 0L) {
  cli::cli_alert_warning(
    "Precincts retained without covariates: {scales::comma(missing_covariates)}."
  )
}

wide_joined <- wide_margins |>
  dplyr::left_join(precinct_covariates, by = "vtd", relationship = "one-to-one") |>
  dplyr::left_join(county_regions, by = "county", relationship = "many-to-one") |>
  dplyr::relocate(nc_region_4, .after = county)

output_cols <- c(
  "county_name", "county", "nc_region_4", "vtd", "total",
  "white_", "black_", "hisp_", "other_", "_rep", "_dem", "_ind", "_lib",
  joint_cells,
  "med_age", "med_inc", "edu_coll", "edu_hsless", "edu_prof", "edu_somecoll",
  "pop_dens", "city_dist", "white_pov", "pop_total", "area_total"
)
wide_output <- wide_joined |>
  dplyr::select(dplyr::all_of(output_cols))

stopifnot(
  !anyDuplicated(wide_output$vtd),
  sum(wide_output$total) == sum(voter_counts$n),
  all(wide_output$total == with(wide_output, white_ + black_ + hisp_ + other_)),
  all(wide_output$total == with(wide_output, `_dem` + `_ind` + `_rep` + `_lib`))
)

geo_output <- readr::read_rds(geo_path) |>
  dplyr::select(vtd, county_nam, fips, geometry)
geo_missing <- setdiff(wide_output$vtd, geo_output$vtd)
if (length(geo_missing) > 0L) {
  cli::cli_abort(c(
    "Wide-table precincts are missing from geometry.",
    "x" = "{.val {geo_missing}}"
  ))
}

wide_output_path <- project_path(config$paths$output, "nc_vtd_wide.rds")
geo_output_path <- project_path(config$paths$output, "nc_vtd_geo.rds")
geojson_output_path <- project_path(config$paths$output, "nc_vtd_geo.geojson")

write_stage_rds(wide_output, wide_output_path)
write_stage_rds(geo_output, geo_output_path)

geojson_output <- geo_output |>
  sf::st_transform(4326)
sf::st_write(geojson_output, geojson_output_path, delete_dsn = TRUE, quiet = TRUE)
cli::cli_alert_success("Wrote {.file {geojson_output_path}}.")

if (isTRUE(config$outputs$write_manifest)) {
  write_output_manifest(c(wide_output_path, geo_output_path, geojson_output_path), project_path(config$manifests$outputs))
} else {
  cli::cli_alert_info("Output manifest not rewritten; set outputs.write_manifest: true after reviewing a successful build.")
}

cli::cli_alert_success(
  "Published {scales::comma(nrow(wide_output))} wide rows and {scales::comma(nrow(geo_output))} geometry rows."
)
