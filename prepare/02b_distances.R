# Written by Codex

# Distances to cities and R1 universities ----
# Output: data/intermediate/cities_dist.rds with GEOID and city_dist in meters.

source("R/nc-utils.R")

require_packages(c("cli", "dplyr", "ggredist", "purrr", "readr", "scales", "sf", "tibble", "tigris", "yaml"))

config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 02b: distances")
r1_path <- project_path(config$paths$intermediate, "r1_coords.rds")
if (!file.exists(r1_path)) {
  cli::cli_abort("Run stage 02a before distances: {.file {r1_path}} is missing.")
}

r1_points <- readr::read_rds(r1_path)
states <- unlist(config$distances$states, use.names = FALSE)
city_points <- ggredist::cities |>
  dplyr::filter(.data$pop_2020 > config$distances$min_city_population, .data$state %in% states)
use_cities <- dplyr::bind_rows(city_points, r1_points)

cli::cli_alert_info(
  "Computing distances from NC {config$tiger$year} cartographic block groups to {scales::comma(nrow(use_cities))} points."
)
tigris::options(tigris_use_cache = TRUE)
block_groups_cb <- tigris::block_groups(
  state = config$state,
  year = config$tiger$year,
  cb = TRUE
) |>
  dplyr::transmute(GEOID, geometry)

distance_matrix <- sf::st_distance(block_groups_cb$geometry, use_cities$geometry)
distances <- tibble::tibble(
  GEOID = block_groups_cb$GEOID,
  city_dist = as.numeric(apply(distance_matrix, 1L, min))
)

write_stage_rds(distances, project_path(config$paths$intermediate, "cities_dist.rds"))
cli::cli_alert_success("Built distances for {scales::comma(nrow(distances))} block groups.")
