# Written by Codex

# Combine wide dataset ----
# Publishes the wide CSV, geometry RDS, and geometry GeoJSON.

source("R/nc-utils.R")
source("R/nc-reference.R")
source("R/nc-precinct-recodes.R")
source("R/nc-combine.R")

require_packages(c("digest", "dplyr", "sf", "tibble", "tidyr"))

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
precinct_geo <- readr::read_rds(geo_path)
combined <- combine_precinct_data(voter_counts, precinct_covariates, precinct_geo)
wide_output <- combined$wide
geo_output <- combined$geo

wide_output_path <- project_path(config$paths$output, "nc_vtd_wide.csv")
geo_output_path <- project_path(config$paths$output, "nc_vtd_geo.rds")
geojson_output_path <- project_path(config$paths$output, "nc_vtd_geo.geojson")

fs::dir_create(fs::path_dir(wide_output_path))
readr::write_csv(wide_output, wide_output_path, na = "")
cli::cli_alert_success("Wrote {.file {wide_output_path}}.")
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
