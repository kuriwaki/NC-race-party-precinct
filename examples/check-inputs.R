# Written by Codex

# Verify an input bundle ----
# Draft helper: source this file, then call verify_inputs().
# Inputs: a reviewed YAML manifest and a local raw-data directory.
# Output: an invisible verification table; no files are changed.
# Scope: exact file inventories under each manifest root, plus size/SHA-256.

verify_inputs <- function(manifest_path, raw_dir = "data/raw") {
  cli::cli_h1("Verify source files")
  manifest_raw <- yaml::read_yaml(manifest_path)
  required_fields <- c("path", "bytes", "sha256")

  if (!identical(manifest_raw$algorithm, "sha256") ||
      length(manifest_raw$files) == 0L ||
      length(manifest_raw$roots) == 0L) {
    cli::cli_abort("Manifest needs algorithm 'sha256', roots, and file entries.")
  }

  files_raw <- purrr::map(manifest_raw$files, tibble::as_tibble) |>
    purrr::list_rbind()
  if (!all(required_fields %in% names(files_raw))) {
    cli::cli_abort("Manifest entries need path, bytes, and sha256 fields.")
  }

  # Manifest paths use forward slashes and stay inside the selected raw root.
  valid_relative <- function(paths) {
    is.character(paths) && !anyNA(paths) &&
      all(nzchar(paths)) &&
      !any(grepl("(^/|^[A-Za-z]:|\\\\|(^|/)\\.{1,2}(/|$)|/$)", paths))
  }

  if (!valid_relative(files_raw$path) ||
      !valid_relative(manifest_raw$roots) ||
      anyDuplicated(files_raw$path) > 0L ||
      !is.numeric(files_raw$bytes) ||
      anyNA(files_raw$bytes) || any(!is.finite(files_raw$bytes)) ||
      any(files_raw$bytes <= 0 | files_raw$bytes != floor(files_raw$bytes)) ||
      !is.character(files_raw$sha256) || anyNA(files_raw$sha256) ||
      any(!grepl("^[0-9a-f]{64}$", files_raw$sha256))) {
    cli::cli_abort("Manifest has invalid paths, duplicate entries, sizes, or hashes.")
  }

  in_scope <- purrr::map_lgl(files_raw$path, function(path) {
    any(startsWith(path, glue::glue("{manifest_raw$roots}/")))
  })
  if (!all(in_scope)) {
    cli::cli_abort("Every manifest file must be inside a declared dataset root.")
  }

  expected_paths <- file.path(raw_dir, files_raw$path)
  missing_paths <- files_raw$path[!file.exists(expected_paths)]
  if (length(missing_paths) > 0L) {
    cli::cli_abort(c(
      "Required source files are missing.",
      "x" = "{.file {missing_paths}}",
      "i" = "Place the selected snapshot under {.file {raw_dir}}."
    ))
  }

  actual_paths <- purrr::map(manifest_raw$roots, function(root) {
    members <- list.files(
      file.path(raw_dir, root), recursive = TRUE, all.files = TRUE,
      no.. = TRUE, include.dirs = FALSE
    )
    file.path(root, members)
  }) |>
    unlist(use.names = FALSE) |>
    unique()
  unexpected_paths <- setdiff(actual_paths, files_raw$path)
  if (length(unexpected_paths) > 0L) {
    cli::cli_abort(c(
      "Unexpected files in a locked input bundle.",
      "x" = "{.file {unexpected_paths}}",
      "i" = "Review the bundle; do not refresh hashes automatically."
    ))
  }

  files_sized <- files_raw |>
    dplyr::mutate(actual_bytes = as.numeric(file.info(expected_paths)$size))
  wrong_sizes <- files_sized |>
    dplyr::filter(is.na(actual_bytes) | actual_bytes != bytes)
  if (nrow(wrong_sizes) > 0L) {
    cli::cli_abort(c(
      "Source file sizes differ from the manifest.",
      "x" = "{.file {wrong_sizes$path}}"
    ))
  }

  cli::cli_alert_info("Hashing {scales::comma(nrow(files_sized))} source files.")
  files_checked <- files_sized |>
    dplyr::mutate(
      actual_sha256 = purrr::map_chr(
        path,
        function(path) digest::digest(
          file = file.path(raw_dir, path), algo = "sha256", serialize = FALSE
        ),
        .progress = "SHA-256"
      ),
      matches = sha256 == actual_sha256
    )
  mismatches <- dplyr::filter(files_checked, !matches)
  if (nrow(mismatches) > 0L) {
    cli::cli_abort(c(
      "Source hashes differ from the reviewed manifest.",
      "x" = "{.file {mismatches$path}}",
      "i" = "Check the snapshot/version before proposing new expected hashes."
    ))
  }

  cli::cli_alert_success(
    "Verified {scales::comma(nrow(files_checked))} files against SHA-256."
  )
  invisible(files_checked)
}
