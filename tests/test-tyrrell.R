# Written by Codex

# Regression against the reviewed, real county example ----
# From the project root: testthat::test_file("tests/test-tyrrell.R", stop_on_failure = TRUE)

source("../R/nc-utils.R")
source("../R/check-inputs.R")
source("../R/nc-reference.R")
source("../R/nc-precinct-recodes.R")
source("../R/nc-geomatch.R")
source("../R/nc-combine.R")
require_packages(c("checkmate", "digest", "dplyr", "geomander", "sf", "tibble", "tidyr"))
testthat::local_edition(3)

testthat::test_that("Tyrrell retains all six precincts and the reviewed spatial assignments", {
  verify_inputs("../manifests/example-tyrrell.yml", "../examples/tyrrell")
  counts <- readr::read_csv("../examples/tyrrell/inputs/voter-counts.csv",
                            col_types = readr::cols(.default = readr::col_character(), n = readr::col_integer()))
  bg <- sf::read_sf("../examples/tyrrell/inputs/block-groups.geojson") |> sf::st_transform(4269)
  precincts <- sf::read_sf("../examples/tyrrell/inputs/precincts.geojson") |> sf::st_transform(2264)
  crosswalk <- block_group_crosswalk(bg, precincts) |> dplyr::arrange(GEOID)
  testthat::expect_identical(crosswalk$vtd, c("371771", "371771", "371772", "371773", "3717715"))
  covariates <- aggregate_precinct_covariates(sf::st_drop_geometry(bg), crosswalk)
  combined <- combine_precinct_data(counts, covariates, precincts)
  wide <- dplyr::arrange(combined$wide, vtd)
  testthat::expect_identical(dim(wide), c(6L, 40L))
  testthat::expect_identical(wide$total, c(119L, 35L, 313L, 14L, 866L, 103L))
  testthat::expect_equal(wide$pop_total, c(1193, NA, 949, NA, 674, 560), tolerance = 0)
  testthat::expect_identical(names(combined$geo), c("vtd", "county_nam", "fips", "geometry"))
  testthat::expect_setequal(combined$geo$vtd, wide$vtd)
})
