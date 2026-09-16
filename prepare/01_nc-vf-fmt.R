# Written by Codex

# Voter counts ----
# Input: a reviewed NC voter-file snapshot under data/raw.
# Output: data/intermediate/nc_vf_agg.rds, one row per vtd/race/party cell.

source("R/nc-utils.R")
source("R/check-inputs.R")
source("R/nc-reference.R")
source("R/nc-precinct-recodes.R")

require_packages(c("arrow", "cli", "dplyr", "glue", "purrr", "readr", "rlang", "scales", "stringr", "tibble", "tidyr", "yaml"))

config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 01: voter counts")
input_manifest <- project_path(config$manifests$inputs)
require_manifest_roots(input_manifest, config$inputs$voter_root)

voter_path <- project_path(config$paths$raw, config$inputs$voter_root)
if (!dir.exists(voter_path)) {
  cli::cli_abort("Voter snapshot directory is missing: {.file {voter_path}}.")
}

nc_ds <- arrow::open_dataset(voter_path)
dataset_names <- names(nc_ds)
county_name_col <- dplyr::case_when(
  "county_name" %in% dataset_names ~ "county_name",
  "county_desc" %in% dataset_names ~ "county_desc",
  TRUE ~ NA_character_
)
required_dataset_cols <- c("race_code", "ethnic_code", "party_cd", "precinct_abbrv", "vtd_abbrv")
missing_dataset_cols <- setdiff(required_dataset_cols, dataset_names)
if (is.na(county_name_col) || length(missing_dataset_cols) > 0L) {
  cli::cli_abort(c(
    "Voter snapshot is missing required columns.",
    "x" = "{.field {c(missing_dataset_cols, if (is.na(county_name_col)) 'county_name/county_desc')}}"
  ))
}

select_exprs <- rlang::list2(
  county_name = rlang::sym(county_name_col),
  precinct_abbrv = rlang::sym("precinct_abbrv"),
  vtd_abbrv = rlang::sym("vtd_abbrv"),
  race_code = rlang::sym("race_code"),
  ethnic_code = rlang::sym("ethnic_code"),
  party_cd = rlang::sym("party_cd")
)
if ("county" %in% dataset_names) {
  select_exprs$county <- rlang::sym("county")
}

counts_query <- nc_ds |>
  dplyr::filter(.data$race_code != "U", .data$ethnic_code != "UN", !is.na(.data$vtd_abbrv)) |>
  dplyr::select(!!!select_exprs) |>
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
  dplyr::count(dplyr::across(dplyr::all_of(c(names(select_exprs), "race", "party"))), name = "n")

counts_initial_raw <- counts_query |>
  dplyr::collect()

county_key <- nc_counties()
counts_named <- counts_initial_raw |>
  dplyr::mutate(
    county_name = stringr::str_to_upper(.data$county_name),
    county_input = if ("county" %in% names(counts_initial_raw)) as.character(.data$county) else NA_character_
  )

counts_with_county <- counts_named |>
  dplyr::select(-dplyr::any_of("county")) |>
  dplyr::left_join(county_key, by = "county_name", relationship = "many-to-one") |>
  dplyr::mutate(
    county = dplyr::coalesce(.data$county_input, .data$county),
    vtd = stringr::str_c(.data$county, .data$precinct_abbrv),
    vtd2 = .data$vtd_abbrv,
    race = factor(.data$race, levels = nc_race_levels()),
    party = factor(.data$party, levels = nc_party_levels())
  ) |>
  dplyr::select(county_name, county, vtd, vtd2, precinct_abbrv, vtd_abbrv, race, party, n)

unknown_counts <- counts_with_county |>
  dplyr::filter(is.na(.data$county) | is.na(.data$race) | is.na(.data$party))
if (nrow(unknown_counts) > 0L) {
  write_join_diagnostic(
    unknown_counts,
    project_path(config$paths$diagnostics, "stage01_unknown_codes.rds")
  )
  cli::cli_abort("Unexpected county, race, or party values found. See stage01_unknown_codes.rds.")
}

counts_recoded <- aggregate_recoded_voters(counts_with_county)

pre_recode_totals <- counts_with_county |>
  dplyr::summarize(n = sum(.data$n), .by = c("county_name", "county", "race", "party"))
post_recode_totals <- counts_recoded |>
  dplyr::summarize(n = sum(.data$n), .by = c("county_name", "county", "race", "party"))
total_check <- pre_recode_totals |>
  dplyr::full_join(
    post_recode_totals,
    by = c("county_name", "county", "race", "party"),
    suffix = c("_pre", "_post"),
    relationship = "one-to-one"
  ) |>
  dplyr::mutate(dplyr::across(c(n_pre, n_post), tidyr::replace_na, 0L)) |>
  dplyr::filter(.data$n_pre != .data$n_post)
if (nrow(total_check) > 0L) {
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
