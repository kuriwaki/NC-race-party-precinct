# Written by Codex

# R1 university points ----
# Validate the supplied point table used in the nearest-city distance.

source("R/nc-utils.R")
source("R/check-inputs.R")

require_packages(c("checkmate", "sf"))
config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 02a: R1 university points")
require_manifest_roots(project_path(config$manifests$inputs), config$inputs$r1_root)

r1_points <- readr::read_rds(project_path(config$paths$raw, config$universities$reviewed_points))
checkmate::assert_class(r1_points, "sf")
checkmate::assert_names(names(r1_points), must.include = "geometry")
checkmate::assert_data_frame(r1_points, min.rows = 1)
if (!all(sf::st_geometry_type(r1_points) %in% c("POINT", "MULTIPOINT"))) {
  cli::cli_abort("R1 university geometry must be point-like.")
}

write_stage_rds(r1_points, project_path(config$paths$intermediate, "r1_coords.rds"))
