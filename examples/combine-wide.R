# Written by Codex

# Combine precinct counts ----
# Draft of stage 04 using invented data; no voter records or file writes.
# Inputs: unique precinct/race/party counts, unique precinct covariates,
# and one region per county. Output: a wide table with 16 cells and margins.
# The production version will add the full covariate schema in PLAN.md.

make_nc_wide <- function(voter_counts, precinct_covariates, county_regions) {
  race_levels <- c("white", "black", "hisp", "other")
  party_levels <- c("dem", "ind", "rep", "lib")
  cell_names <- tidyr::expand_grid(race = race_levels, party = party_levels) |>
    dplyr::transmute(cell = glue::glue("{race}_{party}")) |>
    dplyr::pull(cell) |>
    as.character()

  # Fail before casting factors: unexpected categories must not become NA.
  if (anyNA(voter_counts) ||
      !all(voter_counts$race %in% race_levels) ||
      !all(voter_counts$party %in% party_levels) ||
      any(!is.finite(voter_counts$n)) ||
      any(voter_counts$n < 0 | voter_counts$n != floor(voter_counts$n))) {
    cli::cli_abort("Counts need known race/party codes and nonnegative integers.")
  }
  cell_duplicates <- voter_counts |>
    dplyr::count(vtd, race, party) |>
    dplyr::filter(n > 1L)
  precinct_keys <- voter_counts |>
    dplyr::distinct(vtd, county, county_name)
  if (nrow(cell_duplicates) > 0L || anyDuplicated(precinct_keys$vtd) > 0L) {
    cli::cli_abort("Each precinct needs one county and unique race-party cells.")
  }

  counts_factored <- voter_counts |>
    dplyr::mutate(
      race = factor(race, levels = race_levels),
      party = factor(party, levels = party_levels)
    )
  counts_wide <- counts_factored |>
    tidyr::pivot_wider(
      id_cols = c(county_name, county, vtd),
      names_from = c(race, party), values_from = n,
      names_expand = TRUE, values_fill = 0
    ) |>
    dplyr::select(county_name, county, vtd, dplyr::all_of(cell_names))

  # Compute only from joint cells, before attaching numeric covariates.
  counts_margins <- counts_wide |>
    dplyr::rowwise() |>
    dplyr::mutate(
      total = sum(dplyr::c_across(dplyr::all_of(cell_names))),
      white_ = sum(dplyr::c_across(dplyr::starts_with("white_"))),
      black_ = sum(dplyr::c_across(dplyr::starts_with("black_"))),
      hisp_ = sum(dplyr::c_across(dplyr::starts_with("hisp_"))),
      other_ = sum(dplyr::c_across(dplyr::starts_with("other_"))),
      `_rep` = sum(dplyr::c_across(dplyr::ends_with("_rep"))),
      `_dem` = sum(dplyr::c_across(dplyr::ends_with("_dem"))),
      `_ind` = sum(dplyr::c_across(dplyr::ends_with("_ind"))),
      `_lib` = sum(dplyr::c_across(dplyr::ends_with("_lib"))),
      .after = vtd
    ) |>
    dplyr::ungroup()

  missing_covariates <- sum(!counts_margins$vtd %in% precinct_covariates$vtd)
  missing_regions <- sum(!counts_margins$county %in% county_regions$county)
  if (missing_regions > 0L) {
    cli::cli_abort("Every precinct county needs a region mapping.")
  }
  if (missing_covariates > 0L) {
    cli::cli_alert_warning(
      "Precincts retained without covariates: {scales::comma(missing_covariates)}."
    )
  }

  wide_joined <- counts_margins |>
    dplyr::left_join(
      precinct_covariates, by = "vtd", relationship = "one-to-one"
    ) |>
    dplyr::left_join(
      county_regions, by = "county", relationship = "many-to-one"
    ) |>
    dplyr::relocate(nc_region_4, .after = county)

  stopifnot(
    !anyDuplicated(wide_joined$vtd),
    sum(wide_joined$total) == sum(voter_counts$n),
    all(wide_joined$total == with(wide_joined, white_ + black_ + hisp_ + other_)),
    all(wide_joined$total == with(wide_joined, `_dem` + `_ind` + `_rep` + `_lib`))
  )
  cli::cli_alert_success(
    "Built {scales::comma(nrow(wide_joined))} precinct rows with 16 joint cells."
  )
  wide_joined
}

# Invented example ----
# Both precinct codes and counts are illustrative, not observed records.
# Absent categories become zero; absent covariates remain missing.

example_counts <- tibble::tribble(
  ~county_name, ~county, ~vtd, ~race, ~party, ~n,
  "ALAMANCE", "37001", "37001EXAMPLE1", "white", "dem", 20L,
  "ALAMANCE", "37001", "37001EXAMPLE1", "white", "rep", 30L,
  "ALAMANCE", "37001", "37001EXAMPLE1", "black", "dem", 15L,
  "ALAMANCE", "37001", "37001EXAMPLE2", "hisp", "ind", 10L
)
example_covariates <- tibble::tibble(vtd = "37001EXAMPLE1", med_age = 40)
example_regions <- tibble::tibble(county = "37001", nc_region_4 = "Piedmont")

cli::cli_h1("Illustrate the NC wide table")
example_wide <- make_nc_wide(example_counts, example_covariates, example_regions)
print(example_wide)
