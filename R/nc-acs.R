# Written by Codex

# Median fallback across Census geographies ----
# query is the configured easycensus getter used by stage 02. Keep estimate
# objects intact until the stage extracts point estimates with get_est().

acs_median <- function(table, column, query) {
  estimates <- purrr::map(c("block group", "tract", "county"), function(geo) {
    query(table, geo) |>
      dplyr::filter(.data$race_ethnicity == "total", if (table == "B01002") .data$sex == "total" else TRUE) |>
      dplyr::select(GEOID, estimate)
  })
  estimates[[1]] |>
    dplyr::mutate(tract = stringr::str_sub(.data$GEOID, 1L, 11L), county = stringr::str_sub(.data$GEOID, 1L, 5L)) |>
    dplyr::left_join(
      estimates[[2]], by = dplyr::join_by(tract == GEOID),
      suffix = c("", "_tract"), relationship = "many-to-one"
    ) |>
    dplyr::left_join(
      estimates[[3]], by = dplyr::join_by(county == GEOID),
      suffix = c("", "_county"), relationship = "many-to-one"
    ) |>
    dplyr::transmute(GEOID, "{column}" := dplyr::coalesce(.data$estimate, .data$estimate_tract, .data$estimate_county))
}
