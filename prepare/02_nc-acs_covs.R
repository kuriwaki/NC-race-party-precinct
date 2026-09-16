# Written by Codex

# Block-group covariates ----
# Output: data/intermediate/nc_bg_cov.rds.

source("R/nc-utils.R")

require_packages(c("cli", "dplyr", "easycensus", "readr", "scales", "sf", "stringr", "tibble", "tidyr", "tigris", "yaml"))

config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 02: ACS and TIGER covariates")
distance_path <- project_path(config$paths$intermediate, "cities_dist.rds")
if (!file.exists(distance_path)) {
  cli::cli_abort("Run stage 02b before ACS covariates: {.file {distance_path}} is missing.")
}

options(tigris_use_cache = TRUE)
acs_year <- config$acs$year

cli::cli_alert_info("Retrieving ACS {acs_year} tables and TIGER {config$tiger$year} area data.")
population <- easycensus::cens_get_acs("B01003", geo = "block group", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::select(GEOID, pop = estimate)
area <- tigris::block_groups(config$state, year = config$tiger$year) |>
  sf::st_drop_geometry() |>
  dplyr::transmute(GEOID, area = .data$ALAND / 1609.34^2)

income_bg <- easycensus::cens_get_acs("B19013", geo = "block group", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::filter(.data$race_ethnicity == "total")
income_tract <- easycensus::cens_get_acs("B19013", geo = "tract", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::filter(.data$race_ethnicity == "total")
income_county <- easycensus::cens_get_acs("B19013", geo = "county", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::filter(.data$race_ethnicity == "total")
income <- income_bg |>
  dplyr::select(GEOID, estimate) |>
  dplyr::mutate(
    tract = stringr::str_sub(.data$GEOID, 1L, 11L),
    county = stringr::str_sub(.data$GEOID, 1L, 5L),
    .after = "GEOID"
  ) |>
  dplyr::left_join(
    dplyr::select(income_tract, GEOID, estimate),
    dplyr::join_by(tract == GEOID),
    suffix = c("", "_tract"),
    relationship = "many-to-one"
  ) |>
  dplyr::left_join(
    dplyr::select(income_county, GEOID, estimate),
    dplyr::join_by(county == GEOID),
    suffix = c("", "_county"),
    relationship = "many-to-one"
  ) |>
  dplyr::mutate(estimate = dplyr::coalesce(.data$estimate, .data$estimate_tract, .data$estimate_county)) |>
  dplyr::transmute(GEOID, med_inc = .data$estimate)

education <- easycensus::cens_get_acs("B15003", geo = "block group", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::select(GEOID, estimate, educ = educational_attainment_for_the_population_25_years_over) |>
  dplyr::filter(.data$educ != "total") |>
  dplyr::mutate(
    estimate = easycensus::get_est(.data$estimate),
    educ = dplyr::case_match(
      as.character(.data$educ),
      c("doctorate degree", "professional school degree", "master's degree") ~ "edu_prof",
      "bachelor's degree" ~ "edu_coll",
      c("some college, less than 1 year", "some college, 1 or more years, no degree", "associate's degree") ~ "edu_somecoll",
      .default = "edu_hsless"
    )
  ) |>
  dplyr::summarize(est = sum(.data$estimate), .by = c("GEOID", "educ")) |>
  dplyr::mutate(est = .data$est / sum(.data$est), .by = "GEOID") |>
  tidyr::pivot_wider(names_from = "educ", values_from = "est")

age_bg <- easycensus::cens_get_acs("B01002", geo = "block group", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::filter(.data$race_ethnicity == "total", .data$sex == "total")
age_tract <- easycensus::cens_get_acs("B01002", geo = "tract", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::filter(.data$race_ethnicity == "total", .data$sex == "total")
age_county <- easycensus::cens_get_acs("B01002", geo = "county", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::filter(.data$race_ethnicity == "total", .data$sex == "total")
age <- age_bg |>
  dplyr::select(GEOID, estimate) |>
  dplyr::mutate(
    tract = stringr::str_sub(.data$GEOID, 1L, 11L),
    county = stringr::str_sub(.data$GEOID, 1L, 5L),
    .after = "GEOID"
  ) |>
  dplyr::left_join(
    dplyr::select(age_tract, GEOID, estimate),
    dplyr::join_by(tract == GEOID),
    suffix = c("", "_tract"),
    relationship = "many-to-one"
  ) |>
  dplyr::left_join(
    dplyr::select(age_county, GEOID, estimate),
    dplyr::join_by(county == GEOID),
    suffix = c("", "_county"),
    relationship = "many-to-one"
  ) |>
  dplyr::mutate(estimate = dplyr::coalesce(.data$estimate, .data$estimate_tract, .data$estimate_county)) |>
  dplyr::transmute(GEOID, med_age = .data$estimate)

distances <- readr::read_rds(distance_path)
poverty_raw <- easycensus::cens_get_acs("B17001", geo = "county", state = config$state, check_geo = TRUE, year = acs_year) |>
  dplyr::rename(pov = poverty_status_in_the_past_12_months)
white_poverty <- poverty_raw |>
  dplyr::filter(
    .data$race_ethnicity == "white alone, not hispanic or latino",
    .data$age == "total",
    .data$sex == "total",
    .data$pov != "total"
  ) |>
  dplyr::rename(GEOID_county = GEOID) |>
  dplyr::summarize(
    white_pov = as.numeric(sum(.data$estimate[.data$pov == "income in the past 12 months below poverty level"])) /
      as.numeric(sum(.data$estimate)),
    .by = "GEOID_county"
  )

covariates <- population |>
  dplyr::left_join(area, by = "GEOID", relationship = "one-to-one") |>
  dplyr::left_join(age, by = "GEOID", relationship = "one-to-one") |>
  dplyr::left_join(income, by = "GEOID", relationship = "one-to-one") |>
  dplyr::left_join(education, by = "GEOID", relationship = "one-to-one") |>
  dplyr::mutate(
    dplyr::across(where(~ inherits(.x, "estimate")), easycensus::get_est),
    pop_dens = .data$pop / .data$area
  ) |>
  dplyr::left_join(distances, by = "GEOID", relationship = "one-to-one") |>
  dplyr::mutate(
    city_dist = as.numeric(.data$city_dist),
    med_inc = log(.data$med_inc),
    GEOID_county = stringr::str_sub(.data$GEOID, 1L, 5L)
  ) |>
  dplyr::left_join(white_poverty, by = "GEOID_county", relationship = "many-to-one") |>
  dplyr::select(-GEOID_county)

write_stage_rds(covariates, project_path(config$paths$intermediate, "nc_bg_cov.rds"))
cli::cli_alert_success("Built block-group covariates for {scales::comma(nrow(covariates))} rows.")
