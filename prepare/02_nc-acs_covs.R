# Written by Codex

# Block-group covariates ----
# Output: data/intermediate/nc_bg_cov.rds.

source("R/nc-utils.R")
source("R/nc-acs.R")

require_packages(c("dplyr", "easycensus", "sf", "stringr", "tidyr", "tigris"))

config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 02: ACS and TIGER covariates")
distance_path <- project_path(config$paths$intermediate, "cities_dist.rds")
if (!file.exists(distance_path)) {
  cli::cli_abort("Run stage 02b before ACS covariates: {.file {distance_path}} is missing.")
}

options(tigris_use_cache = TRUE)
acs_year <- config$acs$year

get_acs <- function(table, geo = "block group") {
  easycensus::cens_get_acs(table, geo = geo, state = config$state, year = acs_year, survey = "acs5", check_geo = TRUE)
}

cli::cli_alert_info("Retrieving ACS {acs_year} tables and TIGER {config$tiger$year} area data.")
population <- get_acs("B01003") |>
  dplyr::select(GEOID, pop = estimate)
area <- tigris::block_groups(config$state, year = config$tiger$year) |>
  sf::st_drop_geometry() |>
  dplyr::transmute(GEOID, area = .data$ALAND / 1609.34^2)

income <- acs_median("B19013", "med_inc", get_acs)

education <- get_acs("B15003") |>
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

age <- acs_median("B01002", "med_age", get_acs)

distances <- readr::read_rds(distance_path)
poverty_raw <- get_acs("B17001", "county") |>
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

covariates <- purrr::reduce(
  list(population, area, age, income, education),
  dplyr::left_join, by = "GEOID", relationship = "one-to-one"
) |>
  dplyr::mutate(
    dplyr::across(where(easycensus::is_estimate), easycensus::get_est),
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
