# Written by Codex

# Verify an input bundle ----

read_input_manifest <- function(manifest_path) {
  if (!file.exists(manifest_path)) {
    cli::cli_abort("Input manifest is missing: {.file {manifest_path}}.")
  }
  yaml::read_yaml(manifest_path)
}

validate_manifest_paths <- function(paths) {
  is.character(paths) && !anyNA(paths) &&
    all(nzchar(paths)) &&
    !any(grepl("(^/|^[A-Za-z]:|\\\\|(^|/)\\.{1,2}(/|$)|/$)", paths))
}

verify_inputs <- function(manifest_path, raw_dir = project_path("data", "raw")) {
  cli::cli_h1("Verify source files")
  manifest_raw <- read_input_manifest(manifest_path)
  required_fields <- c("path", "bytes", "sha256")

  pending_roots <- manifest_raw$pending_roots %||% character()
  if (length(pending_roots) > 0L) {
    cli::cli_abort(c(
      "Input manifest still has pending roots.",
      "x" = "{.path {pending_roots}}",
      "i" = "Replace pending entries with reviewed file sizes and SHA-256 hashes before a build."
    ))
  }

  if (!identical(manifest_raw$algorithm, "sha256") ||
      length(manifest_raw$files) == 0L ||
      length(manifest_raw$roots) == 0L) {
    cli::cli_abort("Manifest needs algorithm 'sha256', roots, and file entries.")
  }

  files_raw <- purrr::map(manifest_raw$files, tibble::as_tibble) |>
    purrr::list_rbind()
  directories_raw <- purrr::map(manifest_raw$directories, tibble::as_tibble) |>
    purrr::list_rbind()
  directory_roots <- directories_raw$path %||% character()
  if (!all(required_fields %in% names(files_raw))) {
    cli::cli_abort("Manifest entries need path, bytes, and sha256 fields.")
  }

  if (!validate_manifest_paths(files_raw$path) ||
      !validate_manifest_paths(manifest_raw$roots) ||
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
  if (length(directory_roots) > 0L) {
    if (!identical(manifest_raw$directory_hash_format, "sha256-path-bytes-filehash-v1") ||
        !all(c(required_fields, "file_count") %in% names(directories_raw)) ||
        !validate_manifest_paths(directory_roots) || anyDuplicated(directory_roots) > 0L ||
        !all(directory_roots %in% manifest_raw$roots) ||
        !is.numeric(directories_raw$file_count) || anyNA(directories_raw$file_count) ||
        any(!is.finite(directories_raw$file_count)) ||
        any(directories_raw$file_count <= 0 | directories_raw$file_count != floor(directories_raw$file_count)) ||
        !is.numeric(directories_raw$bytes) || anyNA(directories_raw$bytes) ||
        any(!is.finite(directories_raw$bytes)) ||
        any(directories_raw$bytes <= 0 | directories_raw$bytes != floor(directories_raw$bytes)) ||
        !is.character(directories_raw$sha256) || anyNA(directories_raw$sha256) ||
        any(!grepl("^[0-9a-f]{64}$", directories_raw$sha256))) {
      cli::cli_abort("Manifest has invalid directory paths, file counts, sizes, hashes, or hash format.")
    }
    overlapping_files <- purrr::map_lgl(files_raw$path, function(path) {
      any(startsWith(path, glue::glue("{directory_roots}/")))
    })
    if (any(overlapping_files)) {
      cli::cli_abort("Lock a source root by directory checksum or by individual files, not both.")
    }
  }
  empty_roots <- manifest_raw$roots[!purrr::map_lgl(manifest_raw$roots, function(root) {
    root %in% directory_roots || any(startsWith(files_raw$path, glue::glue("{root}/")))
  })]
  if (length(empty_roots) > 0L) {
    cli::cli_abort(c(
      "Every declared source root needs reviewed files or a directory checksum.",
      "x" = "{.path {empty_roots}}"
    ))
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

  actual_paths <- purrr::map(setdiff(manifest_raw$roots, directory_roots), function(root) {
    root_path <- file.path(raw_dir, root)
    if (!dir.exists(root_path)) {
      return(character())
    }
    members <- list.files(
      root_path, recursive = TRUE, all.files = TRUE,
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
        function(path) hash_file(file.path(raw_dir, path)),
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

  directory_checks <- purrr::map(directory_roots, function(root) {
    cli::cli_alert_info("Hashing dataset directory {.file {root}}.")
    expected <- dplyr::filter(directories_raw, path == root)
    actual <- hash_directory(file.path(raw_dir, root))
    if (expected$file_count != actual$file_count || expected$bytes != actual$bytes ||
        expected$sha256 != actual$sha256) {
      cli::cli_abort(c(
        "Source directory differs from the reviewed manifest.",
        "x" = "{.file {root}}",
        "i" = "Check for missing, extra, renamed, or changed files; do not refresh hashes automatically."
      ))
    }
    tibble::tibble(
      path = root, bytes = expected$bytes, sha256 = expected$sha256,
      actual_bytes = actual$bytes, actual_sha256 = actual$sha256,
      matches = TRUE, file_count = actual$file_count
    )
  }) |>
    purrr::list_rbind()
  verified_inputs <- dplyr::bind_rows(
    dplyr::mutate(files_checked, file_count = 1L), directory_checks
  )
  cli::cli_alert_success("Verified {scales::comma(sum(verified_inputs$file_count))} files against SHA-256.")
  invisible(verified_inputs)
}

require_manifest_roots <- function(manifest_path, roots) {
  manifest_raw <- read_input_manifest(manifest_path)
  missing_roots <- setdiff(roots, manifest_raw$roots %||% character())
  if (length(missing_roots) > 0L) {
    cli::cli_abort(c(
      "Input manifest does not lock every required source root.",
      "x" = "{.path {missing_roots}}",
      "i" = "Add reviewed hashes before running the pipeline."
    ))
  }
  invisible(roots)
}

`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
