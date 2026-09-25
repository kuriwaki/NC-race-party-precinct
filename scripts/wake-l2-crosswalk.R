# Written with Claude

# Wake County precinct crosswalk from L2 geocodes ----
# Not a pipeline stage and not listed in config/pipeline.yml: run manually from
# the repository root when the L2 extract or the locked inputs change. The
# pipeline itself never reads L2; it reads only the generated R source below.
#
# Reads:
#   - data/raw/ncvoter_2025-08-02 (locked voter snapshot; Wake partition only)
#   - data/raw/SBE_PRECINCTS_20250225 (locked SBE geometry)
#   - data/raw/l2/VM2Uniform--NC--2025-10-03_Wake.parquet (local L2 extract,
#     ignored by Git; keep it at this path so every copy of the repo matches)
# Writes:
#   - R/nc-wake-crosswalk.R: wake_precinct_crosswalk(), one row per Wake
#     vtd_abbrv, tracked and used by apply_nc_precinct_recodes()
#   - data/diagnostics/wake_l2_destinations.rds: every vtd_abbrv x prec_id
#     count (local only), for revisiting the modal assignment
#
# Method: take voters in the stage 01 universe, join them to L2 by ncid, place
# each at its L2 residence coordinates within a February 2025 SBE polygon, and
# map each vtd_abbrv to the polygon holding the most of its voters.

source("R/nc-utils.R")
source("R/check-inputs.R")

require_packages(c("arrow", "dplyr", "glue", "sf", "stringr"))
config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Wake precinct crosswalk from L2 geocodes")
input_manifest <- project_path(config$manifests$inputs)
require_manifest_roots(input_manifest, config$inputs$voter_root)
require_manifest_roots(input_manifest, config$inputs$sbe_root)

wake_fips <- "37183"
l2_path <- project_path(config$paths$raw, "l2", "VM2Uniform--NC--2025-10-03_Wake.parquet")
if (!file.exists(l2_path)) {
  cli::cli_abort("Local L2 extract not found at {.file {l2_path}}.")
}

# Geometry ----

sbe_wake <- sf::read_sf(project_path(config$paths$raw, config$inputs$sbe_root)) |>
  dplyr::filter(.data$county_nam == "WAKE") |>
  dplyr::select(prec_id)

duplicate_prec_ids <- sbe_wake |>
  sf::st_drop_geometry() |>
  dplyr::count(prec_id) |>
  dplyr::filter(.data$n > 1L)
if (nrow(duplicate_prec_ids) > 0L) {
  cli::cli_abort("Duplicate Wake prec_id values in the SBE geometry: {.val {duplicate_prec_ids$prec_id}}.")
}

# Voters and L2 points ----
# Same universe filters as prepare/01_nc-vf-fmt.R.

wake_voters <- open_voter_dataset(project_path(config$paths$raw, config$inputs$voter_root)) |>
  dplyr::filter(
    .data$county_name == "WAKE",
    .data$race_code != "U",
    .data$ethnic_code != "UN",
    !is.na(.data$vtd_abbrv)
  ) |>
  dplyr::select(ncid, vtd_abbrv) |>
  dplyr::collect()

l2_points <- arrow::open_dataset(l2_path) |>
  dplyr::filter(
    !is.na(.data$Residence_Addresses_Latitude),
    !is.na(.data$Residence_Addresses_Longitude)
  ) |>
  dplyr::select(Voters_StateVoterID, Residence_Addresses_Latitude, Residence_Addresses_Longitude) |>
  dplyr::collect()

voters_with_points <- wake_voters |>
  dplyr::inner_join(l2_points, by = c("ncid" = "Voters_StateVoterID"), relationship = "one-to-one")

voters_located <- voters_with_points |>
  sf::st_as_sf(coords = c("Residence_Addresses_Longitude", "Residence_Addresses_Latitude"), crs = 4326) |>
  sf::st_transform(sf::st_crs(sbe_wake)) |>
  sf::st_join(sbe_wake, join = sf::st_within) |>
  sf::st_drop_geometry() |>
  dplyr::filter(!is.na(.data$prec_id))

if (anyDuplicated(voters_located$ncid) > 0L) {
  cli::cli_abort("Some voters fall within more than one Wake SBE polygon.")
}
cli::cli_alert_info(
  "Placed {scales::comma(nrow(voters_located))} of {scales::comma(nrow(wake_voters))} Wake voters ({scales::percent(nrow(voters_located) / nrow(wake_voters), accuracy = 0.1)}) in a February 2025 SBE precinct."
)

# Modal destination per code ----

destination_counts <- voters_located |>
  dplyr::count(vtd_abbrv, prec_id, name = "n") |>
  dplyr::mutate(total = sum(.data$n), .by = "vtd_abbrv")

modal_destinations <- destination_counts |>
  dplyr::slice_max(order_by = n, n = 1L, with_ties = FALSE, by = "vtd_abbrv")

crosswalk <- modal_destinations |>
  dplyr::transmute(
    county = wake_fips,
    vtd_abbrv,
    corrected_vtd = stringr::str_c(wake_fips, .data$prec_id),
    overridden = .data$prec_id != .data$vtd_abbrv,
    n_voters = .data$n,
    total_voters = .data$total,
    share = round(.data$n / .data$total, 3)
  ) |>
  dplyr::arrange(.data$vtd_abbrv)

# Checks and aggregate impact ----

uncovered_codes <- setdiff(unique(wake_voters$vtd_abbrv), crosswalk$vtd_abbrv)
if (length(uncovered_codes) > 0L) {
  cli::cli_abort("Wake vtd_abbrv codes with no L2-placed voters: {.val {uncovered_codes}}. Add reviewed rows before using the crosswalk.")
}

overridden_codes <- crosswalk |>
  dplyr::filter(.data$overridden)
overridden_in_geometry <- intersect(overridden_codes$vtd_abbrv, sbe_wake$prec_id)
if (length(overridden_in_geometry) > 0L) {
  cli::cli_alert_warning("Overridden codes that also exist as February 2025 precincts: {.val {overridden_in_geometry}}.")
}

empty_precincts <- setdiff(sbe_wake$prec_id, modal_destinations$prec_id)

impact <- crosswalk |>
  dplyr::summarize(
    codes = dplyr::n(),
    placed_elsewhere = sum(.data$total_voters - .data$n_voters),
    total = sum(.data$total_voters),
    .by = "overridden"
  )
impact_overridden <- dplyr::filter(impact, .data$overridden)

cli::cli_alert_info(
  "{nrow(crosswalk)} Wake codes; {nrow(overridden_codes)} overridden, {nrow(crosswalk) - nrow(overridden_codes)} map to their own precinct."
)
cli::cli_alert_info(
  "Overridden codes: {scales::comma(impact_overridden$placed_elsewhere)} of {scales::comma(impact_overridden$total)} L2-placed voters assigned outside their L2-located precinct."
)
cli::cli_alert_warning(
  "{length(empty_precincts)} February 2025 Wake precincts are no code's modal destination and will have no voters: {.val {empty_precincts}}."
)

# Write ----

crosswalk_rows <- glue::glue_data(
  crosswalk,
  '    "{county}", "{vtd_abbrv}", "{corrected_vtd}", {overridden}, {n_voters}L, {total_voters}L, {share}'
)
crosswalk_source <- c(
  "# Generated by scripts/wake-l2-crosswalk.R; do not edit by hand.",
  "",
  "# Wake precinct crosswalk ----",
  "# One row per Wake voter-file vtd_abbrv in the stage 01 universe, mapped to the",
  "# February 2025 SBE precinct where most of its L2-geocoded voters live.",
  "# `overridden` marks codes whose modal precinct differs from the code itself.",
  "# Counts are L2-placed voters (2025-08-02 snapshot, 2025-10-03 L2 extract).",
  "#",
  "# TODO: Voters in the overridden codes are split across several current",
  "# precincts. Modal assignment places",
  glue::glue("# {impact_overridden$placed_elsewhere} of {impact_overridden$total} L2-placed voters in these codes outside their"),
  glue::glue("# L2-located precinct, leaves {length(empty_precincts)} February 2025 precincts with no voters,"),
  "# and the split differs by race. Revisit with an allocation by L2 shares.",
  "",
  "wake_precinct_crosswalk <- function() {",
  "  tibble::tribble(",
  "    ~county, ~vtd_abbrv, ~corrected_vtd, ~overridden, ~n_voters, ~total_voters, ~share,",
  paste0(crosswalk_rows, c(rep(",", length(crosswalk_rows) - 1L), "")),
  "  )",
  "}"
)

crosswalk_path <- project_path("R", "nc-wake-crosswalk.R")
readr::write_lines(crosswalk_source, crosswalk_path)
write_join_diagnostic(destination_counts, project_path(config$paths$diagnostics, "wake_l2_destinations.rds"))
cli::cli_alert_success("Wrote {.file {crosswalk_path}} with {nrow(crosswalk)} rows.")
