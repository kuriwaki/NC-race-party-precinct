# Written by Codex

# Project paths ----

project_root <- function() {
  root <- getOption("nc_race_party_precinct.root")
  if (!is.null(root)) {
    return(normalizePath(root, mustWork = TRUE))
  }

  cwd <- normalizePath(getwd(), mustWork = TRUE)
  if (file.exists(file.path(cwd, "NC-race-party-precinct.Rproj"))) {
    return(cwd)
  }

  cli::cli_abort(
    "Run from the NC-race-party-precinct project root or set {.code options(nc_race_party_precinct.root = ...)}."
  )
}

project_path <- function(...) {
  file.path(project_root(), ...)
}

ensure_pipeline_dirs <- function() {
  dirs <- c(
    "data/raw", "data/intermediate", "release", "data/diagnostics",
    "cache", "logs"
  )
  purrr::walk(project_path(dirs), dir.create, recursive = TRUE, showWarnings = FALSE)
  invisible(dirs)
}

# Config ----

read_pipeline_config <- function(path = project_path("config", "pipeline.yml")) {
  if (!file.exists(path)) {
    cli::cli_abort("Pipeline config is missing: {.file {path}}.")
  }
  yaml::read_yaml(path)
}

require_packages <- function(packages) {
  missing_packages <- packages[!purrr::map_lgl(packages, requireNamespace, quietly = TRUE)]
  if (length(missing_packages) > 0L) {
    cli::cli_abort(c(
      "Install required R packages before running this stage.",
      "x" = "{.pkg {missing_packages}}"
    ))
  }
  invisible(packages)
}

write_stage_rds <- function(x, path, compress = "xz") {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_rds(x, path, compress = compress)
  cli::cli_alert_success("Wrote {.file {path}}.")
  invisible(path)
}

write_yaml_file <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(x, path)
  cli::cli_alert_success("Wrote {.file {path}}.")
  invisible(path)
}

# Hash manifests ----

hash_file <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

hash_directory <- function(path) {
  if (!dir.exists(path)) {
    cli::cli_abort("Input directory is missing: {.file {path}}.")
  }
  relative_paths <- list.files(
    path, recursive = TRUE, all.files = TRUE, no.. = TRUE, include.dirs = FALSE
  ) |>
    sort(method = "radix")
  if (length(relative_paths) == 0L || any(grepl("[\t\r\n]", relative_paths))) {
    cli::cli_abort("Input directory must contain files with no tabs or newlines in their names.")
  }

  absolute_paths <- file.path(path, relative_paths)
  file_bytes <- as.numeric(file.info(absolute_paths)$size)
  file_hashes <- purrr::map_chr(absolute_paths, hash_file)
  byte_labels <- scales::number(file_bytes, accuracy = 1, big.mark = "", decimal.mark = ".")

  # Directory checksum v1: sort relative paths by radix order, then hash UTF-8
  # records of path<TAB>bytes<TAB>file-sha256<LF>, including the final LF.
  # Per-file hashes are computed locally but only the directory hash is stored.
  records <- glue::glue("{relative_paths}\t{byte_labels}\t{file_hashes}\n", .trim = FALSE)
  directory_text <- as.character(glue::glue_collapse(records, sep = ""))
  list(
    file_count = length(relative_paths),
    bytes = sum(file_bytes),
    sha256 = digest::digest(enc2utf8(directory_text), algo = "sha256", serialize = FALSE)
  )
}

file_manifest <- function(paths, root_dir = project_root()) {
  normalized_paths <- normalizePath(paths, mustWork = TRUE)
  normalized_root <- normalizePath(root_dir, mustWork = TRUE)
  rel_paths <- sub(glue::glue("^{normalized_root}/?"), "", normalized_paths)

  tibble::tibble(
    path = rel_paths,
    bytes = as.numeric(file.info(normalized_paths)$size),
    sha256 = purrr::map_chr(normalized_paths, hash_file)
  )
}

write_output_manifest <- function(
  paths = project_path("release", c("nc_vtd_wide.rds", "nc_vtd_geo.rds", "nc_vtd_geo.geojson")),
  manifest_path = project_path("manifests", "outputs.yml")
) {
  missing_paths <- paths[!file.exists(paths)]
  if (length(missing_paths) > 0L) {
    cli::cli_abort(c(
      "Cannot write an output manifest until all published outputs exist.",
      "x" = "{.file {missing_paths}}"
    ))
  }

  manifest <- list(
    schema_version = 1,
    algorithm = "sha256",
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    files = purrr::transpose(file_manifest(paths))
  )
  write_yaml_file(manifest, manifest_path)
}

# Diagnostics ----

write_join_diagnostic <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  readr::write_rds(x, path, compress = "xz")
  cli::cli_alert_info("Wrote diagnostic {.file {path}}.")
  invisible(path)
}
