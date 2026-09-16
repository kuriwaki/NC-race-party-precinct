# Written by Codex

# Manifest schema ----

read_input_manifest <- function(manifest_path) {
  if (!fs::file_exists(manifest_path)) {
    cli::cli_abort("Input manifest is missing: {.file {manifest_path}}.")
  }
  yaml::read_yaml(manifest_path)
}

assert_manifest_paths <- function(paths) {
  checkmate::assert_character(paths, any.missing = FALSE, min.chars = 1, unique = TRUE)
  if (any(grepl("(^/|^[A-Za-z]:|\\\\|[\t\r\n]|(^|/)\\.{1,2}(/|$)|/$)", paths))) {
    cli::cli_abort("Manifest paths must be relative, without dot segments or control characters.")
  }
}

manifest_entries <- function(manifest) {
  checkmate::assert_choice(manifest$algorithm, "sha256")
  checkmate::assert_character(manifest$roots, min.len = 1, any.missing = FALSE)
  assert_manifest_paths(manifest$roots)
  if (length(manifest$pending_roots) > 0L) {
    cli::cli_abort("Input manifest still has pending roots: {.path {manifest$pending_roots}}.")
  }

  files <- dplyr::bind_rows(manifest$files) |>
    dplyr::mutate(file_count = 1L)
  entries <- dplyr::bind_rows(file = files, directory = dplyr::bind_rows(manifest$directories), .id = "type")
  checkmate::assert_names(names(entries), must.include = c("path", "bytes", "sha256", "file_count"))
  checkmate::assert_data_frame(entries, min.rows = 1)
  assert_manifest_paths(entries$path)
  checkmate::assert_integerish(entries$bytes, lower = 1, tol = 0, any.missing = FALSE)
  checkmate::assert_integerish(entries$file_count, lower = 1, tol = 0, any.missing = FALSE)
  checkmate::assert_character(entries$sha256, pattern = "^[0-9a-f]{64}$", any.missing = FALSE)

  directory_roots <- entries$path[entries$type == "directory"]
  if (length(directory_roots) > 0L) {
    checkmate::assert_choice(manifest$directory_hash_format, "sha256-path-bytes-filehash-v1")
    checkmate::assert_subset(directory_roots, manifest$roots)
  }
  file_paths <- entries$path[entries$type == "file"]
  in_root <- function(path, roots) any(fs::path_has_parent(path, roots))
  if (!all(purrr::map_lgl(file_paths, in_root, roots = setdiff(manifest$roots, directory_roots))) ||
      any(purrr::map_lgl(file_paths, in_root, roots = directory_roots))) {
    cli::cli_abort("Each file must belong to a declared root that is not already locked by a directory checksum.")
  }
  covered_roots <- manifest$roots[purrr::map_lgl(manifest$roots, function(root) {
    root %in% directory_roots || any(fs::path_has_parent(file_paths, root))
  })]
  checkmate::assert_set_equal(covered_roots, manifest$roots)
  entries
}

# Verify supplied files ----

verify_inputs <- function(manifest_path, raw_dir = project_path("data", "raw")) {
  cli::cli_h1("Verify source files")
  manifest <- read_input_manifest(manifest_path)
  entries <- tryCatch(manifest_entries(manifest), error = function(error) {
    cli::cli_abort(c("Invalid input manifest {.file {manifest_path}}.", "x" = conditionMessage(error)))
  })
  directory_roots <- entries$path[entries$type == "directory"]
  missing_roots <- manifest$roots[!fs::dir_exists(fs::path(raw_dir, manifest$roots))]
  missing_files <- entries$path[entries$type == "file" & !fs::file_exists(fs::path(raw_dir, entries$path))]
  if (length(c(missing_roots, missing_files)) > 0L) {
    cli::cli_abort(c("Required source inputs are missing.", "x" = "{.path {c(missing_roots, missing_files)}}"))
  }
  actual_files <- fs::dir_ls(
    fs::path(raw_dir, setdiff(manifest$roots, directory_roots)),
    recurse = TRUE, all = TRUE, type = c("file", "symlink")
  ) |>
    fs::path_rel(start = raw_dir) |>
    as.character()
  unexpected_files <- setdiff(actual_files, entries$path[entries$type == "file"])
  if (length(unexpected_files) > 0L) {
    cli::cli_abort(c("Unexpected files in a locked input bundle.", "x" = "{.file {unexpected_files}}"))
  }

  cli::cli_alert_info("Checking {scales::comma(sum(entries$file_count))} source files.")
  measured <- purrr::map2(entries$path, entries$type, function(path, type) {
    full_path <- fs::path(raw_dir, path)
    if (type == "directory") {
      return(tibble::as_tibble(hash_directory(full_path)))
    }
    tibble::tibble(file_count = 1L, bytes = as.numeric(fs::file_size(full_path)), sha256 = hash_file(full_path))
  }) |>
    purrr::list_rbind() |>
    dplyr::rename_with(~ glue::glue("actual_{.x}"))
  verified <- dplyr::bind_cols(entries, measured) |>
    dplyr::mutate(matches = bytes == actual_bytes & sha256 == actual_sha256 & file_count == actual_file_count)
  mismatches <- dplyr::filter(verified, !matches)
  if (nrow(mismatches) > 0L) {
    cli::cli_abort(c(
      "Source files or directories differ from the reviewed manifest.",
      "x" = "{.path {mismatches$path}}",
      "i" = "Check for changed, missing, extra, or renamed files; do not refresh hashes automatically."
    ))
  }
  cli::cli_alert_success("Verified {scales::comma(sum(verified$file_count))} files against SHA-256.")
  invisible(verified)
}

require_manifest_roots <- function(manifest_path, roots) {
  missing_roots <- setdiff(roots, read_input_manifest(manifest_path)$roots)
  if (length(missing_roots) > 0L) {
    cli::cli_abort(c("Input manifest does not lock every required source root.", "x" = "{.path {missing_roots}}"))
  }
  invisible(roots)
}
