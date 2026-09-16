# Written by Codex

# Acquire and verify inputs ----
# Default behavior is verification only. Current public downloads are moving
# endpoints, so historical snapshots should be placed under data/raw and locked
# in manifests/inputs.yml before running stages 01--04.

source("R/nc-utils.R")
source("R/check-inputs.R")
source("R/nc-reference.R")

require_packages(c("cli", "digest", "dplyr", "glue", "purrr", "readr", "scales", "stringr", "tibble", "yaml"))

config <- read_pipeline_config()
ensure_pipeline_dirs()

input_manifest <- project_path(config$manifests$inputs)
required_roots <- unlist(config$inputs$required_roots, use.names = FALSE)

cli::cli_h1("Stage 00: inputs")
cli::cli_alert_info("Checking required source roots in {.file {config$manifests$inputs}}.")
require_manifest_roots(input_manifest, required_roots)
verified_inputs <- verify_inputs(input_manifest, raw_dir = project_path(config$paths$raw))

# Optional current NCSBE download helpers ----

download_current_voter_zip <- function(county_name, output_dir = project_path(config$paths$raw, "ncvoter_current")) {
  county_key <- nc_counties()
  county_row <- county_key |>
    dplyr::filter(.data$county_name == stringr::str_to_upper(county_name))
  if (nrow(county_row) != 1L) {
    cli::cli_abort("Unknown NC county: {.val {county_name}}.")
  }

  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  url <- glue::glue(
    "https://s3.amazonaws.com/dl.ncsbe.gov/data/ncvoter{county_row$sbe_download_id}.zip"
  )
  zip_path <- file.path(output_dir, glue::glue("ncvoter{county_row$sbe_download_id}.zip"))
  utils::download.file(url, zip_path, quiet = TRUE, mode = "wb")
  cli::cli_alert_success("Downloaded current moving-endpoint voter ZIP: {.file {zip_path}}.")
  invisible(zip_path)
}

download_sbe_precinct_zip <- function(
  version = config$snapshots$sbe_precincts,
  output_dir = project_path(config$paths$raw)
) {
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  zip_name <- glue::glue("{version}.zip")
  zip_path <- file.path(output_dir, zip_name)
  url <- glue::glue("https://s3.amazonaws.com/dl.ncsbe.gov/PrecinctMaps/{zip_name}")
  utils::download.file(url, zip_path, quiet = TRUE, mode = "wb")
  cli::cli_alert_success("Downloaded SBE precinct ZIP: {.file {zip_path}}.")
  invisible(zip_path)
}

cli::cli_alert_success("Stage 00 verified {scales::comma(sum(verified_inputs$file_count))} locked input files.")
