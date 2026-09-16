# Written by Codex

# R1 university points ----
# Builds or verifies the local R1 point table used in the nearest-city distance.

source("R/nc-utils.R")
source("R/check-inputs.R")

require_packages(c("cli", "dplyr", "readr", "sf", "stringr", "tibble", "yaml"))

config <- read_pipeline_config()
ensure_pipeline_dirs()

cli::cli_h1("Stage 02a: R1 university points")
input_manifest <- project_path(config$manifests$inputs)
require_manifest_roots(input_manifest, config$inputs$r1_root)

mode <- config$universities$mode
output_path <- project_path(config$paths$intermediate, "r1_coords.rds")

validate_r1_points <- function(points) {
  if (!inherits(points, "sf") || !"geometry" %in% names(points)) {
    cli::cli_abort("R1 points must be an sf object with point geometry.")
  }
  if (!all(sf::st_geometry_type(points) %in% c("POINT", "MULTIPOINT"))) {
    cli::cli_abort("R1 university geometry must be point-like.")
  }
  if (nrow(points) == 0L) {
    cli::cli_abort("R1 point table has no rows.")
  }
  points
}

normalize_names <- function(x) {
  names(x) <- names(x) |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("[^a-z0-9]+", "_") |>
    stringr::str_replace_all("(^_|_$)", "")
  x
}

filter_college_points <- function(points) {
  filtered <- points
  if ("naics_desc" %in% names(filtered)) {
    filtered <- filtered |>
      dplyr::filter(stringr::str_detect(stringr::str_to_lower(.data$naics_desc), "college|university|professional"))
  }
  if ("deg_grant" %in% names(filtered)) {
    filtered <- filtered |>
      dplyr::filter(.data$deg_grant %in% c(1, "1"))
  }
  if ("hi_offer" %in% names(filtered)) {
    filtered <- filtered |>
      dplyr::filter(.data$hi_offer %in% c(11, 12, "11", "12"))
  }
  if ("inst_size" %in% names(filtered)) {
    filtered <- filtered |>
      dplyr::filter(.data$inst_size %in% c(2, 3, 4, 5, "2", "3", "4", "5"))
  }
  filtered
}

if (identical(mode, "reviewed_points")) {
  raw_path <- project_path(config$paths$raw, config$universities$reviewed_points)
  if (!file.exists(raw_path)) {
    cli::cli_abort("Reviewed R1 point file is missing: {.file {raw_path}}.")
  }
  r1_points <- readr::read_rds(raw_path) |>
    validate_r1_points()
  write_stage_rds(r1_points, output_path)
} else if (identical(mode, "reviewed_crosswalk")) {
  require_packages(c("readxl"))
  source_geometry_path <- project_path(config$paths$raw, config$universities$source_geometry)
  r1_workbook_path <- project_path(config$paths$raw, config$universities$r1_workbook)
  crosswalk_path <- project_path(config$universities$crosswalk)
  missing_paths <- c(source_geometry_path, r1_workbook_path, crosswalk_path)[
    !file.exists(c(source_geometry_path, r1_workbook_path, crosswalk_path))
  ]
  if (length(missing_paths) > 0L) {
    cli::cli_abort(c(
      "University source files are missing.",
      "x" = "{.file {missing_paths}}"
    ))
  }

  college_points <- sf::read_sf(source_geometry_path) |>
    normalize_names() |>
    filter_college_points()
  workbook <- readxl::read_excel(r1_workbook_path) |>
    normalize_names()
  crosswalk <- yaml::read_yaml(crosswalk_path)$matches |>
    tibble::as_tibble()

  if (nrow(crosswalk) == 0L || !all(c("source_id", "r1_name") %in% names(crosswalk))) {
    cli::cli_abort("Reviewed university crosswalk needs source_id and r1_name entries.")
  }
  source_id_column <- config$universities$source_id_column
  if (!source_id_column %in% names(college_points)) {
    cli::cli_abort("University source geometry is missing ID column {.field {source_id_column}}.")
  }

  r1_name_col <- intersect(c("r1_name", "name", "institution"), names(workbook))[1]
  if (is.na(r1_name_col)) {
    cli::cli_abort("R1 workbook needs one of these name columns: r1_name, name, institution.")
  }
  r1_names <- workbook |>
    dplyr::transmute(r1_name = as.character(.data[[r1_name_col]]), in_workbook = TRUE) |>
    dplyr::distinct()
  reviewed_crosswalk <- crosswalk |>
    dplyr::left_join(r1_names, by = "r1_name", relationship = "many-to-one")
  missing_reviewed_names <- reviewed_crosswalk |>
    dplyr::filter(is.na(.data$in_workbook))
  if (nrow(missing_reviewed_names) > 0L) {
    cli::cli_abort("Some reviewed R1 names are absent from the workbook.")
  }

  college_points_keyed <- college_points |>
    dplyr::mutate(source_id = as.character(.data[[source_id_column]]))
  r1_points <- college_points_keyed |>
    dplyr::inner_join(
      dplyr::mutate(crosswalk, source_id = as.character(.data$source_id)),
      by = "source_id",
      relationship = "one-to-one"
    ) |>
    dplyr::select(r1_name, source_id, dplyr::any_of(c("name", "state")), geometry) |>
    sf::st_transform(4269) |>
    validate_r1_points()

  write_stage_rds(r1_points, output_path)
} else {
  cli::cli_abort("Unknown university build mode in config: {.val {mode}}.")
}
