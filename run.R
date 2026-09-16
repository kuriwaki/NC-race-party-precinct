# Written by Codex

# Run the NC pipeline ----

options(nc_race_party_precinct.root = normalizePath(getwd(), mustWork = TRUE))

source("R/nc-utils.R")

require_packages()

config <- read_pipeline_config()
stages <- unlist(config$run$stages, use.names = FALSE)

cli::cli_h1("NC race-party-precinct build")
cli::cli_alert_info("Running stages: {paste(stages, collapse = ', ')}.")

stage_files <- list(
  "00" = "prepare/00_nc_download.R",
  "01" = "prepare/01_nc-vf-fmt.R",
  "02a" = "prepare/02a_nc-universities.R",
  "02b" = "prepare/02b_distances.R",
  "02" = "prepare/02_nc-acs_covs.R",
  "03" = "prepare/03_nc-geomatch.R",
  "04" = "prepare/04_nc-wide_combine.R"
)

unknown_stages <- setdiff(stages, names(stage_files))
if (length(unknown_stages) > 0L) {
  cli::cli_abort("Unknown stage labels in config: {.val {unknown_stages}}.")
}

purrr::walk(stages, function(stage) {
  cli::cli_rule(glue::glue("Stage {stage}"))
  source(stage_files[[stage]], local = new.env(parent = globalenv()))
})

cli::cli_alert_success("NC pipeline run finished.")
