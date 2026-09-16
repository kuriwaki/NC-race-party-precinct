# Written by Codex

# Focused checks without source data or network access ----
# From the repository root: testthat::test_file("tests/test-pipeline.R")

source("../R/nc-utils.R")
source("../R/check-inputs.R")
source("../R/nc-acs.R")
source("../R/nc-precinct-recodes.R")
require_packages(c("checkmate", "digest", "dplyr", "easycensus", "stringr", "tibble"))
testthat::local_edition(3)

testthat::test_that("directory checksums preserve v1 and detect changed inventories", {
  raw <- withr::local_tempdir()
  fs::dir_create(fs::path(raw, "voters", c("county_name=ONE", "county_name=TWO")))
  paths <- fs::path(raw, "voters", c("county_name=ONE", "county_name=TWO"), "part-0.parquet")
  purrr::walk2(c("abc", "def"), paths, readr::write_file)
  expected <- hash_directory(fs::path(raw, "voters"))
  # Independently calculated from the documented path/size/file-hash records.
  testthat::expect_identical(expected$sha256, "169ff587f10c660f887ea98357b8c30a139de2f9e02d65c22566833fa2360bb9")
  manifest <- list(algorithm = "sha256", roots = "voters",
                   directory_hash_format = "sha256-path-bytes-filehash-v1",
                   directories = list(c(list(path = "voters"), expected)))
  manifest_path <- fs::path(raw, "manifest.yml")
  yaml::write_yaml(manifest, manifest_path, precision = 17)
  verify <- function() verify_inputs(manifest_path, raw)
  testthat::expect_equal(sum(verify()$file_count), 2L, tolerance = 0)
  readr::write_file("abd", paths[1])
  testthat::expect_error(verify(), "differ")
  readr::write_file("abc", paths[1])
  fs::file_move(paths[1], fs::path(raw, "voters", "renamed.parquet"))
  testthat::expect_error(verify(), "differ")
  fs::file_move(fs::path(raw, "voters", "renamed.parquet"), paths[1])
  if (.Platform$OS.type != "windows") {
    fs::link_create(paths[1], fs::path(raw, "voters", "extra-link.parquet"))
    testthat::expect_error(verify(), "differ")
    fs::file_delete(fs::path(raw, "voters", "extra-link.parquet"))
  }
  readr::write_file("extra", fs::path(raw, "voters", ".DS_Store"))
  testthat::expect_error(verify(), "differ")
  fs::file_delete(c(fs::path(raw, "voters", ".DS_Store"), paths[2]))
  testthat::expect_error(verify(), "differ")
})

testthat::test_that("file manifests reject malformed entries and unlisted files", {
  raw <- withr::local_tempdir()
  fs::dir_create(fs::path(raw, "source"))
  readr::write_file("abc", fs::path(raw, "source", "input.dat"))
  file <- list(path = "source/input.dat", bytes = 3L, sha256 = hash_file(fs::path(raw, "source", "input.dat")))
  manifest <- list(algorithm = "sha256", roots = "source", files = list(file))
  manifest_path <- fs::path(raw, "manifest.yml")
  yaml::write_yaml(manifest, manifest_path)
  testthat::expect_true(all(verify_inputs(manifest_path, raw)$matches))
  for (change in list(list(bytes = Inf), list(bytes = 1.5), list(bytes = NA_real_),
                      list(sha256 = "wrong"), list(path = "../input.dat"))) {
    invalid <- list(algorithm = "sha256", roots = "source", files = list(utils::modifyList(file, change)))
    testthat::expect_error(manifest_entries(invalid))
  }
  readr::write_file("extra", fs::path(raw, "source", "extra.dat"))
  testthat::expect_error(verify_inputs(manifest_path, raw), "Unexpected")
})

testthat::test_that("ACS medians use block group, tract, then county and retain missingness", {
  query <- function(table, geo) {
    county <- c("37001", "37003", "37005", "37007")
    ids <- switch(geo, "block group" = glue::glue("{county}0001001"),
                  tract = glue::glue("{county}000100"), county = county)
    values <- switch(geo, "block group" = c(10, NA, NA, NA),
                     tract = c(100, 20, NA, NA), county = c(1000, 2000, 30, NA))
    totals <- tibble::tibble(GEOID = as.character(ids), race_ethnicity = "total",
                             estimate = easycensus::estimate(values, se = ifelse(is.na(values), NA, 1)), sex = "total")
    other_race <- dplyr::mutate(totals, race_ethnicity = "other")
    if (table == "B01002") {
      return(dplyr::bind_rows(totals, other_race, dplyr::mutate(totals, sex = "male")))
    }
    dplyr::select(dplyr::bind_rows(totals, other_race), -sex)
  }
  for (table in c("B19013", "B01002")) {
    result <- acs_median(table, "median", query)
    testthat::expect_s3_class(result$median, "estimate")
    testthat::expect_equal(easycensus::get_est(result$median), c(10, 20, 30, NA), tolerance = 0)
  }
})

testthat::test_that("precinct recoding preserves county totals", {
  counts <- tibble::tibble(county_name = "WAKE", county = "37183", vtd = c("37183A", "37183B"),
                           vtd2 = c("01-01", "01-02"), race = "white", party = "dem", n = c(2L, 3L))
  recoded <- aggregate_recoded_voters(counts)
  testthat::expect_equal(recoded$n, 5L, tolerance = 0)
  testthat::expect_equal(county_voter_totals(recoded), county_voter_totals(counts), tolerance = 0)
})
