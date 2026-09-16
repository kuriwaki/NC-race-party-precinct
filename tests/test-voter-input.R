# Written by Codex

# Arrow metadata regression with invented voter codes ----
source("../R/nc-utils.R")
require_packages(c("arrow", "digest", "dplyr", "tibble"))
testthat::local_edition(3)

testthat::test_that("voter queries ignore row-specific R attributes without changing source bytes", {
  root <- withr::local_tempdir()
  partition <- fs::dir_create(fs::path(root, "county_name=TYRRELL"))
  path <- fs::path(partition, "part-0.parquet")
  rows <- tibble::tibble(
    county = stats::setNames(rep("37177", 3), c("first", "second", "third")),
    precinct_abbrv = c("01", "01", "02"),
    party_cd = c("DEM", "DEM", "REP")
  )
  arrow::write_parquet(rows, path)
  before <- hash_file(path)
  original <- arrow::open_dataset(root)
  testthat::expect_length(original$schema$metadata$r$columns$county$attributes$names, 3L)

  clean <- open_voter_dataset(root)
  testthat::expect_true(clean$schema$Equals(original$schema, check_metadata = FALSE))
  testthat::expect_null(clean$schema$metadata$r)
  testthat::expect_no_warning(result <- clean |>
    dplyr::filter(party_cd == "DEM") |>
    dplyr::count(county_name, county, precinct_abbrv, name = "n") |>
    dplyr::collect())
  testthat::expect_equal(result, tibble::tibble(
    county_name = "TYRRELL", county = "37177", precinct_abbrv = "01", n = 2L
  ), tolerance = 0)
  testthat::expect_identical(hash_file(path), before)
})
