# Written by Codex

# Voter counts ----
# Input: the locked, county-partitioned NC voter snapshot under data/raw.
# Output: data/intermediate/nc_vf_agg.rds, one row per vtd/race/party cell.

source("R/nc-utils.R")
source("R/check-inputs.R")
source("R/nc-precinct-recodes.R")

require_packages(c("arrow", "checkmate", "dplyr", "stringr"))
config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 01: voter counts")
require_manifest_roots(project_path(config$manifests$inputs), config$inputs$voter_root)

nc_ds <- open_voter_dataset(project_path(config$paths$raw, config$inputs$voter_root))
required_cols <- c("county_name", "county", "precinct_abbrv", "vtd_abbrv", "race_code", "ethnic_code", "party_cd")
checkmate::assert_names(names(nc_ds), must.include = required_cols)

counts_initial <- nc_ds |>
  dplyr::filter(.data$race_code != "U", .data$ethnic_code != "UN", !is.na(.data$vtd_abbrv)) |>
  dplyr::select(dplyr::all_of(required_cols)) |>
  dplyr::mutate(
    race = dplyr::case_when(
      .data$ethnic_code == "HL" ~ "hisp",
      .data$race_code == "W" ~ "white",
      .data$race_code == "B" ~ "black",
      .data$race_code %in% c("A", "I", "M", "O", "P") ~ "other",
      TRUE ~ NA_character_
    ),
    party = dplyr::case_when(
      .data$party_cd == "DEM" ~ "dem",
      .data$party_cd == "UNA" ~ "ind",
      .data$party_cd == "REP" ~ "rep",
      .data$party_cd == "LIB" ~ "lib",
      TRUE ~ "ind"
    )
  ) |>
  dplyr::count(county_name, county, precinct_abbrv, vtd_abbrv, race, party, name = "n") |>
  dplyr::collect()

counts_with_county <- counts_initial |>
  dplyr::mutate(
    county_name = stringr::str_to_upper(.data$county_name),
    county = as.character(.data$county),
    vtd = stringr::str_c(.data$county, .data$precinct_abbrv),
    vtd2 = .data$vtd_abbrv,
    race = factor(.data$race, levels = nc_race_levels()),
    party = factor(.data$party, levels = nc_party_levels())
  ) |>
  dplyr::select(county_name, county, vtd, vtd2, precinct_abbrv, vtd_abbrv, race, party, n)

unknown_counts <- counts_with_county |>
  dplyr::filter(is.na(.data$county) | is.na(.data$race) | is.na(.data$party))
if (nrow(unknown_counts) > 0L) {
  write_join_diagnostic(unknown_counts, project_path(config$paths$diagnostics, "stage01_unknown_codes.rds"))
  cli::cli_abort("Unexpected county, race, or party values found. See stage01_unknown_codes.rds.")
}

counts_recoded <- aggregate_recoded_voters(counts_with_county)
if (!dplyr::setequal(county_voter_totals(counts_with_county), county_voter_totals(counts_recoded))) {
  cli::cli_abort("Precinct recoding changed county/race/party totals.")
}

write_join_diagnostic(
  counts_with_county |>
    dplyr::distinct(county, precinct_abbrv, vtd_abbrv, vtd, vtd2),
  project_path(config$paths$diagnostics, "stage01_precinct_recode_keys.rds")
)
write_stage_rds(counts_recoded, project_path(config$paths$intermediate, "nc_vf_agg.rds"))
cli::cli_alert_success(
  "Built {scales::comma(nrow(counts_recoded))} voter count cells across {scales::comma(dplyr::n_distinct(counts_recoded$vtd))} precincts."
)
