# Written by Codex

# Race and party definitions ----

nc_race_levels <- function() {
  c("white", "black", "hisp", "other")
}

nc_party_levels <- function() {
  c("dem", "ind", "rep", "lib")
}

nc_joint_cell_names <- function() {
  tidyr::expand_grid(race = nc_race_levels(), party = nc_party_levels()) |>
    dplyr::transmute(cell = glue::glue("{race}_{party}")) |>
    dplyr::pull(cell) |>
    as.character()
}

# Voter precinct rules ----

county_voter_totals <- function(voter_counts) {
  voter_counts |>
    dplyr::summarize(n = sum(.data$n), .by = c("county_name", "county", "race", "party")) |>
    dplyr::filter(.data$n != 0)
}

counties_using_vtd_abbrv <- function() {
  c("GASTON", "WAKE", "HARNETT", "PENDER", "COLUMBUS")
}

apply_nc_precinct_recodes <- function(voter_counts) {
  required_cols <- c("county_name", "county", "vtd", "vtd2", "race", "party", "n")
  missing_cols <- setdiff(required_cols, names(voter_counts))
  if (length(missing_cols) > 0L) {
    cli::cli_abort("Missing columns for precinct recoding: {.field {missing_cols}}.")
  }

  switch_keys <- voter_counts |>
    dplyr::filter(county_name %in% counties_using_vtd_abbrv()) |>
    dplyr::transmute(
      county_name,
      vtd,
      vtd2,
      new_vtd = stringr::str_c(county, vtd2)
    ) |>
    dplyr::distinct()

  recoded <- voter_counts |>
    dplyr::left_join(
      switch_keys,
      by = c("county_name", "vtd", "vtd2"),
      relationship = "many-to-one"
    ) |>
    dplyr::mutate(
      vtd = dplyr::coalesce(new_vtd, vtd),
      vtd = dplyr::if_else(vtd == "37157ED" & vtd2 == "ED-1", "37157ED-1", vtd),
      vtd = dplyr::if_else(vtd == "37157ST" & vtd2 == "LK-2", "37157LK-2", vtd),
      vtd = dplyr::if_else(vtd == "37157ED" & vtd2 == "LK-2", "37157LK-2", vtd),
      vtd = dplyr::if_else(vtd == "37157ST" & vtd2 == "MA", "37157MA", vtd),
      vtd = dplyr::if_else(vtd == "37061WLLC" & vtd2 == "LOCK", "37061LOCK", vtd),
      vtd = dplyr::if_else(vtd == "37061WLLC" & vtd2 == "ROCK", "37061ROCK", vtd),
      vtd = dplyr::if_else(vtd == "37061WLLC" & vtd2 == "WALL", "37061WALL", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "EH1", "37181EH1", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "EH2", "37181EH1", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "NH2", "37181NH1", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "NH1", "37181NH", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "SH1", "37181SH1", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "SH2", "37181SH2", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "WH1", "37181WH", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "HTOP", "37181HTOP", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "KITT", "37181KITT", vtd),
      vtd = dplyr::if_else(county == "37181" & vtd2 == "SCRK", "37181SCRK", vtd),
      vtd = dplyr::if_else(county == "37085" & vtd2 == "PR17", "37085PR31", vtd),
      vtd = dplyr::if_else(county == "37085" & vtd2 == "PR27", "37085PR32", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 == "P01", "37047P01A", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 == "P02", "37047P02B", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 == "P16", "37047P16B", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 == "P20", "37047P20A", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 == "P22", "37047P22A", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 == "P25", "37047P25B", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 == "P26", "37047P26B", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 %in% c("P10", "P12"), "37047P112", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 %in% c("P03", "P04"), "37047P34", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 %in% c("P05", "P13"), "37047P513", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 %in% c("P18", "P21"), "37047P82", vtd),
      vtd = dplyr::if_else(county == "37047" & vtd2 %in% c("P08", "P09"), "37047P89", vtd),
      vtd = dplyr::if_else(vtd == "37089CV", "37089HV-2", vtd),
      vtd = dplyr::if_else(vtd == "37141NB01", "37141NB02", vtd),
      vtd = dplyr::if_else(vtd == "37141UU17", "37141UU18", vtd),
      vtd = dplyr::if_else(vtd == "37141MH07", "37141NB02", vtd),
      vtd = dplyr::if_else(vtd == "37141PL10", "37141UU18", vtd),
      vtd = dplyr::if_else(vtd == "371790020B", "37179020B", vtd),
      vtd = dplyr::if_else(vtd == "371790044", "37179044", vtd),
      vtd = dplyr::if_else(vtd == "371790045", "37179045", vtd),
      vtd = dplyr::if_else(vtd == "37175CC.1", "37175CC", vtd),
      vtd = dplyr::if_else(vtd == "37175RE.1", "37175RE", vtd),
      vtd_wake = dplyr::if_else(county == "37183", stringr::word(vtd, 1, sep = "-"), NA_character_),
      vtd = dplyr::coalesce(vtd_wake, vtd)
    )

  recoded |>
    dplyr::select(-new_vtd, -vtd_wake)
}

aggregate_recoded_voters <- function(voter_counts) {
  voter_counts |>
    apply_nc_precinct_recodes() |>
    dplyr::count(county_name, county, vtd, race, party, wt = n, name = "n")
}

# Geometry rules ----

haywood_gaston_geometry_edits <- function() {
  tibble::tribble(
    ~county_nam, ~prec_id, ~prec_id_recode, ~enr_desc,
    "HAYWOOD", "BE-1", "BE1", "BEAVERDAM 1",
    "HAYWOOD", "BE-2", "BE2", "BEAVERDAM 2",
    "HAYWOOD", "BE-3", "BE3", "BEAVERDAM 3",
    "HAYWOOD", "BE-4", "BE4", "BEAVERDAM 4",
    "HAYWOOD", "BE-7", "BE7", "BEAVERDAM 7",
    "HAYWOOD", "BE56", "BE5-6", "BEAVERDAM 5/6",
    "HAYWOOD", "CL-N", "CLN", "CLYDE NORTH",
    "HAYWOOD", "CL-S", "CLS", "CLYDE SOUTH",
    "GASTON", "04-1", "04", "FOREST HEIGHTS",
    "GASTON", "06-1", "06", "MYRTLE",
    "GASTON", "14-1", "14", "GARDNER PARK",
    "GASTON", "18-1", "18", "ASHBROOK",
    "GASTON", "19-1", "19", "SOUTH GASTONIA",
    "GASTON", "21-1", "21", "BESSEMER CITY #2",
    "GASTON", "25-1", "25", "BELMONT #3",
    "GASTON", "26-1", "26", "CATAWBA HEIGHTS",
    "GASTON", "28-1", "28", "CRAMERTON",
    "GASTON", "29-1", "29", "NEW HOPE",
    "GASTON", "30-1", "30", "MCADENVILLE",
    "GASTON", "32-1", "32", "LOWELL"
  )
}
