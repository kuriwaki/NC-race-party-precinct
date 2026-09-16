# Written by Codex

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
