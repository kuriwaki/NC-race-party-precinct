# Written with Claude

# Wake precinct map for review ----
# Builds examples/wake/wake-precincts.geojson from the stage 01 output and the
# locked SBE geometry, so the Wake crosswalk can be inspected on GitHub.
# Run from the repository root after stage 01. Aggregate counts only; no L2.
# Fill colors follow GitHub's simplestyle properties:
#   red    = no voters assigned
#   orange = receives an overridden code
#   grey   = holds its own code only

source("R/nc-utils.R")
source("R/nc-reference.R")
source("R/nc-precinct-recodes.R")
source("R/nc-wake-crosswalk.R")
source("R/nc-geomatch.R")

require_packages(c("dplyr", "rmapshaper", "sf", "stringr", "tidyr"))
config <- read_pipeline_config()

cli::cli_h1("Wake example GeoJSON")

agg_path <- project_path(config$paths$intermediate, "nc_vf_agg.rds")
if (!file.exists(agg_path)) {
  cli::cli_abort("Run stage 01 first: {.file {agg_path}} is missing.")
}

# Counts ----

wake_counts <- readr::read_rds(agg_path) |>
  dplyr::filter(.data$county == "37183")

wake_by_race <- wake_counts |>
  dplyr::summarize(n = sum(.data$n), .by = c("vtd", "race")) |>
  tidyr::pivot_wider(names_from = "race", values_from = "n", values_fill = 0, names_prefix = "voters_")

wake_totals <- wake_counts |>
  dplyr::summarize(voters_total = sum(.data$n), .by = "vtd") |>
  dplyr::left_join(wake_by_race, by = "vtd", relationship = "one-to-one")

override_destinations <- wake_precinct_crosswalk() |>
  dplyr::filter(.data$overridden) |>
  dplyr::distinct(vtd = .data$corrected_vtd) |>
  dplyr::mutate(override_destination = TRUE)

# Geometry ----

wake_geo <- sf::read_sf(project_path(config$paths$raw, config$inputs$sbe_root)) |>
  dplyr::filter(.data$county_nam == "WAKE") |>
  prepare_precinct_geometry() |>
  dplyr::select(vtd, prec_id)

unplaced_vtds <- setdiff(wake_totals$vtd, wake_geo$vtd)
if (length(unplaced_vtds) > 0L) {
  cli::cli_abort("Wake voter keys with no SBE polygon: {.val {unplaced_vtds}}.")
}

wake_map <- wake_geo |>
  dplyr::left_join(wake_totals, by = "vtd", relationship = "one-to-one") |>
  dplyr::left_join(override_destinations, by = "vtd", relationship = "one-to-one") |>
  dplyr::mutate(
    super_precinct = stringr::str_c("37183", stringr::word(.data$prec_id, 1L, sep = "-")),
    dplyr::across(dplyr::starts_with("voters_"), ~ dplyr::coalesce(.x, 0)),
    override_destination = dplyr::coalesce(.data$override_destination, FALSE),
    status = dplyr::case_when(
      .data$voters_total == 0 ~ "no voters",
      .data$override_destination ~ "receives overridden code",
      TRUE ~ "own code"
    ),
    fill = dplyr::case_when(
      .data$status == "no voters" ~ "#d7301f",
      .data$status == "receives overridden code" ~ "#fc8d59",
      TRUE ~ "#bdbdbd"
    ),
    `fill-opacity` = 0.6,
    stroke = "#636363",
    `stroke-width` = 0.5
  ) |>
  rmapshaper::ms_simplify(keep = config$geometry$simplify_keep, keep_shapes = TRUE) |>
  sf::st_transform(4326)

status_counts <- wake_map |>
  sf::st_drop_geometry() |>
  dplyr::count(status)
cli::cli_alert_info(
  "{nrow(wake_map)} Wake precincts: {glue::glue_collapse(glue::glue_data(status_counts, '{n} {status}'), sep = ', ')}."
)

# Write ----

out_path <- project_path("examples", "wake", "wake-precincts.geojson")
fs::dir_create(fs::path_dir(out_path))
sf::write_sf(wake_map, out_path, delete_dsn = TRUE, layer_options = "COORDINATE_PRECISION=6")

out_size <- fs::file_size(out_path)
if (out_size > fs::as_fs_bytes("1MiB")) {
  cli::cli_alert_warning("{.file {out_path}} is {out_size}, above the proposed 1 MiB limit; lower the simplify keep.")
}
cli::cli_alert_success("Wrote {.file {out_path}} ({out_size}).")
