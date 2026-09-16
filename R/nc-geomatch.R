# Written by Codex

# Prepare precinct keys ----
# Source nc-reference.R and nc-precinct-recodes.R before calling.
# Match edits by county/name, as in the source pipeline. Exclude the lookup's
# old prec_id so the join preserves the source prec_id without .x/.y suffixes.

prepare_precinct_geometry <- function(precinct_geo_raw) {
  precinct_geo_raw |>
    dplyr::select(-dplyr::starts_with("Shape_Leng"), -dplyr::any_of("of_prec_id")) |>
    dplyr::left_join(
      dplyr::select(haywood_gaston_geometry_edits(), -prec_id),
      by = c("county_nam", "enr_desc"),
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      prec_id = dplyr::coalesce(.data$prec_id_recode, .data$prec_id),
      prec_id_wake = dplyr::if_else(.data$county_nam == "WAKE", stringr::word(.data$prec_id, 1L, sep = "-"), NA_character_),
      prec_id = dplyr::coalesce(.data$prec_id_wake, .data$prec_id)
    ) |>
    dplyr::select(-dplyr::any_of(c("prec_id_recode", "prec_id_wake"))) |>
    dplyr::left_join(nc_county_geometry_reference(), by = "county_nam", relationship = "many-to-one") |>
    dplyr::mutate(vtd = stringr::str_c(.data$fips, .data$prec_id), .after = "enr_desc")
}

# Match and aggregate block groups ----
# Shared by stage 03 and the offline county example. Full block groups are
# assigned to their greatest-overlap precinct, then weighted by population.

block_group_crosswalk <- function(acs_geo, precinct_geo) {
  matches <- geomander::geo_match(from = acs_geo, to = precinct_geo, method = "area")
  tibble::tibble(GEOID = acs_geo$GEOID, vtd = precinct_geo$vtd[matches])
}

aggregate_precinct_covariates <- function(bg_cov, crosswalk) {
  bg_cov |>
    dplyr::left_join(crosswalk, by = "GEOID", relationship = "one-to-one") |>
    dplyr::summarize(
      dplyr::across(-c(GEOID, pop, area), ~ weighted.mean(.x, .data$pop)),
      pop_total = sum(.data$pop),
      area_total = sum(.data$area),
      .by = "vtd"
    )
}
