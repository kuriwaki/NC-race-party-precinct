# Written by Codex

# Run the offline Tyrrell County example ----
# From the repository root: Rscript examples/tyrrell/run.R

source("R/nc-utils.R")
source("R/check-inputs.R")
source("R/nc-reference.R")
source("R/nc-precinct-recodes.R")
source("R/nc-geomatch.R")
source("R/nc-combine.R")
require_packages(c("checkmate", "digest", "dplyr", "geomander", "rmapshaper", "sf", "tibble", "tidyr"))

example_dir <- project_path("examples", "tyrrell")
manifest_path <- project_path("manifests", "example-tyrrell.yml")
manifest <- read_input_manifest(manifest_path)
verified <- verify_inputs(manifest_path, example_dir)
cli::cli_h1("Tyrrell County: match and combine")

voter_counts <- readr::read_csv(fs::path(example_dir, "inputs", "voter-counts.csv"),
                               col_types = readr::cols(.default = readr::col_character(), n = readr::col_integer()))
block_groups <- sf::read_sf(fs::path(example_dir, "inputs", "block-groups.geojson")) |>
  sf::st_transform(manifest$block_group_crs)
precincts <- sf::read_sf(fs::path(example_dir, "inputs", "precincts.geojson")) |>
  sf::st_transform(manifest$precinct_crs)

crosswalk <- block_group_crosswalk(block_groups, precincts)
precinct_covariates <- aggregate_precinct_covariates(sf::st_drop_geometry(block_groups), crosswalk)
geometry <- rmapshaper::ms_simplify(precincts, keep = manifest$simplify_keep, keep_shapes = TRUE)
combined <- combine_precinct_data(voter_counts, precinct_covariates, geometry)
stopifnot(nrow(combined$wide) == manifest$expected$precincts,
          nrow(combined$geo) == manifest$expected$precincts,
          sum(combined$wide$total) == manifest$expected$voter_total,
          sum(combined$wide$pop_total, na.rm = TRUE) == manifest$expected$population)

output_dir <- project_path("release", "tyrrell")
write_stage_rds(combined$geo, fs::path(output_dir, "nc_vtd_geo.rds"))
readr::write_csv(combined$wide, fs::path(output_dir, "nc_vtd_wide.csv"), na = "")
sf::st_write(sf::st_transform(combined$geo, 4326), fs::path(output_dir, "nc_vtd_geo.geojson"),
             delete_dsn = TRUE, quiet = TRUE, layer_options = "RFC7946=YES")

input_bytes <- as.numeric(object.size(list(voter_counts, block_groups, precincts)))
output_bytes <- as.numeric(object.size(combined))
cli::cli_alert_success("Built {nrow(combined$wide)} precincts, {ncol(combined$wide)} table columns, and {scales::comma(sum(combined$wide$total))} counted registrations.")
cli::cli_alert_info("Tracked input files: {scales::comma(sum(verified$bytes))} bytes. R objects: {scales::comma(input_bytes)} input bytes; {scales::comma(output_bytes)} output bytes.")
cli::cli_alert_info("These object sizes exclude R, packages, and temporary allocations. Results: {.path {output_dir}}.")
