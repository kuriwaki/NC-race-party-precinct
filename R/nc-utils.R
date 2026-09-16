# Written by Codex

# Project paths ----

project_root <- function() {
  root <- getOption("nc_race_party_precinct.root")
  if (!is.null(root)) {
    return(fs::path_real(root))
  }

  cwd <- fs::path_real(getwd())
  if (fs::file_exists(fs::path(cwd, "NC-race-party-precinct.Rproj"))) {
    return(cwd)
  }

  cli::cli_abort(
    "Run from the NC-race-party-precinct project root or set {.code options(nc_race_party_precinct.root = ...)}."
  )
}

project_path <- function(...) {
  fs::path(project_root(), ...)
}

ensure_pipeline_dirs <- function() {
  dirs <- c(
    "data/raw", "data/intermediate", "release", "data/diagnostics",
    "cache", "logs"
  )
  fs::dir_create(project_path(dirs))
  invisible(dirs)
}

# Config ----

read_pipeline_config <- function(path = project_path("config", "pipeline.yml")) {
  if (!file.exists(path)) {
    cli::cli_abort("Pipeline config is missing: {.file {path}}.")
  }
  yaml::read_yaml(path)
}

require_packages <- function(packages = character()) {
  required <- unique(c("cli", "fs", "glue", "purrr", "readr", "scales", "yaml", packages))
  missing_packages <- required[!vapply(required, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_packages) > 0L) {
    cli::cli_abort(c(
      "Install required R packages before running this stage.",
      "x" = "{.pkg {missing_packages}}"
    ))
  }
  invisible(required)
}

write_stage_rds <- function(x, path, compress = "xz") {
  fs::dir_create(fs::path_dir(path))
  readr::write_rds(x, path, compress = compress)
  cli::cli_alert_success("Wrote {.file {path}}.")
  invisible(path)
}

write_yaml_file <- function(x, path) {
  fs::dir_create(fs::path_dir(path))
  yaml::write_yaml(x, path, precision = 17)
  cli::cli_alert_success("Wrote {.file {path}}.")
  invisible(path)
}

# Hash manifests ----

hash_file <- function(path) {
  digest::digest(file = path, algo = "sha256", serialize = FALSE)
}

hash_directory <- function(path) {
  if (!fs::dir_exists(path)) {
    cli::cli_abort("Input directory is missing: {.file {path}}.")
  }
  relative_paths <- fs::dir_ls(path, recurse = TRUE, all = TRUE, type = c("file", "symlink")) |>
    fs::path_rel(start = path) |>
    as.character() |>
    sort(method = "radix")
  if (length(relative_paths) == 0L || any(grepl("[\t\r\n]", relative_paths))) {
    cli::cli_abort("Input directory must contain files with no tabs or newlines in their names.")
  }

  absolute_paths <- fs::path(path, relative_paths)
  file_bytes <- as.numeric(fs::file_size(absolute_paths))
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
  tibble::tibble(
    path = as.character(fs::path_rel(fs::path_real(paths), start = fs::path_real(root_dir))),
    bytes = as.numeric(fs::file_size(paths)),
    sha256 = purrr::map_chr(paths, hash_file)
  )
}

write_output_manifest <- function(
  paths = project_path("release", c("nc_vtd_wide.csv", "nc_vtd_geo.rds", "nc_vtd_geo.geojson")),
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
  fs::dir_create(fs::path_dir(path))
  readr::write_rds(x, path, compress = "xz")
  cli::cli_alert_info("Wrote diagnostic {.file {path}}.")
  invisible(path)
}
