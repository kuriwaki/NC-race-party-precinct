# Written by Codex

# Combine precinct counts, covariates, and geometry ----
# Shared by stage 04 and the offline county example.
# Source nc-reference.R and nc-precinct-recodes.R before calling.

combine_precinct_data <- function(voter_counts, precinct_covariates, precinct_geo) {
  county_regions <- nc_regions_4()
  joint_cells <- nc_joint_cell_names()

  counts_factored <- voter_counts |>
    dplyr::mutate(
      race = factor(.data$race, levels = nc_race_levels()),
      party = factor(.data$party, levels = nc_party_levels())
    )
  counts_wide <- counts_factored |>
    tidyr::pivot_wider(
      id_cols = c(county_name, county, vtd),
      names_from = c(race, party),
      values_from = n,
      names_expand = TRUE,
      values_fill = 0
    ) |>
    dplyr::select(county_name, county, vtd, dplyr::all_of(joint_cells))

  # Keep integer count columns while summing all rows at once.
  wide_margins <- counts_wide |>
    dplyr::mutate(
      total = as.integer(rowSums(dplyr::pick(dplyr::all_of(joint_cells)))),
      white_ = as.integer(rowSums(dplyr::pick(dplyr::starts_with("white_")))),
      black_ = as.integer(rowSums(dplyr::pick(dplyr::starts_with("black_")))),
      hisp_ = as.integer(rowSums(dplyr::pick(dplyr::starts_with("hisp_")))),
      other_ = as.integer(rowSums(dplyr::pick(dplyr::starts_with("other_")))),
      `_rep` = as.integer(rowSums(dplyr::pick(dplyr::ends_with("_rep")))),
      `_dem` = as.integer(rowSums(dplyr::pick(dplyr::ends_with("_dem")))),
      `_ind` = as.integer(rowSums(dplyr::pick(dplyr::ends_with("_ind")))),
      `_lib` = as.integer(rowSums(dplyr::pick(dplyr::ends_with("_lib")))),
      .after = vtd
    )

  missing_covariates <- sum(!wide_margins$vtd %in% precinct_covariates$vtd)
  missing_regions <- sum(!wide_margins$county %in% county_regions$county)
  if (missing_regions > 0L) {
    cli::cli_abort("Every county in the voter counts needs a region mapping.")
  }
  if (missing_covariates > 0L) {
    cli::cli_alert_warning(
      "Precincts retained without covariates: {scales::comma(missing_covariates)}."
    )
  }

  wide_joined <- wide_margins |>
    dplyr::left_join(precinct_covariates, by = "vtd", relationship = "one-to-one") |>
    dplyr::left_join(county_regions, by = "county", relationship = "many-to-one") |>
    dplyr::relocate(nc_region_4, .after = county)

  output_cols <- c(
    "county_name", "county", "nc_region_4", "vtd", "total",
    "white_", "black_", "hisp_", "other_", "_rep", "_dem", "_ind", "_lib",
    joint_cells,
    "med_age", "med_inc", "edu_coll", "edu_hsless", "edu_prof", "edu_somecoll",
    "pop_dens", "city_dist", "white_pov", "pop_total", "area_total"
  )
  wide_output <- wide_joined |>
    dplyr::select(dplyr::all_of(output_cols))

  stopifnot(
    !anyDuplicated(wide_output$vtd),
    sum(wide_output$total) == sum(voter_counts$n),
    all(wide_output$total == with(wide_output, white_ + black_ + hisp_ + other_)),
    all(wide_output$total == with(wide_output, `_dem` + `_ind` + `_rep` + `_lib`))
  )

  geo_output <- precinct_geo |>
    dplyr::select(vtd, county_nam, fips, geometry)
  geo_missing <- setdiff(wide_output$vtd, geo_output$vtd)
  if (length(geo_missing) > 0L) {
    cli::cli_abort(c(
      "Wide-table precincts are missing from geometry.",
      "x" = "{.val {geo_missing}}"
    ))
  }
  list(wide = wide_output, geo = geo_output)
}
