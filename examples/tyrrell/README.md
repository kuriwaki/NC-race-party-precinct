# Tyrrell County: an offline example

Tyrrell has six precincts in the February 25, 2025 SBE bundle. The frozen
2023 ACS five-year block-group estimates total 3,376 residents, and the voter
count table contains 1,450 registrations after the pipeline's filters. These
are the example's source vintages, not current population or registration totals.

The example starts with precinct race-by-party counts and prepared block-group
covariates. It runs the spatial matching and final combination used by the
[full pipeline](../../config/pipeline.yml), using the shared
[matching functions](../../R/nc-geomatch.R) from [stage 03](../../prepare/03_nc-geomatch.R)
and [combination function](../../R/nc-combine.R) from [stage 04](../../prepare/04_nc-wide_combine.R).
It needs no individual voter records, Census downloads, API key, or files outside
this repository. Package installation requires internet access.

## Run it

Open `NC-race-party-precinct.Rproj` and work from the repository root.
Install the example's dependencies once:

```r
# Written by Codex
install.packages(c(
  "checkmate", "cli", "digest", "dplyr", "fs", "geomander", "glue", "purrr",
  "readr", "rmapshaper", "scales", "sf", "tibble", "tidyr", "yaml"
))
source("examples/tyrrell/run.R")
```

Or, with those packages installed:

```sh
Rscript examples/tyrrell/run.R
```

[run.R](run.R) checks all three input hashes against
[manifests/example-tyrrell.yml](../../manifests/example-tyrrell.yml), matches
block groups to their greatest-overlap precinct with `geomander::geo_match()`,
population-weights the covariates, simplifies the output geometry, and constructs
the wide table with race/party margins. All six precincts remain in the outputs.

The expected message `Precincts retained without covariates: 2` illustrates the
matching rule: Kilkenny (`3717714`) and South Fork (`3717716`) receive no block
groups. Their counts and geometry remain, with missing covariates. One of the
five block groups has zero population and land area; it is retained and has zero
weight. These are properties of the real example, not errors to fill with zeros.

## Included files and columns

Only the three exact paths below are exceptions in [.gitignore](../../.gitignore).
Their descriptions, roles, byte counts, and SHA-256 hashes are in the
[example manifest](../../manifests/example-tyrrell.yml). There is one file per
input type; geometry is stored as GeoJSON instead of a multi-file shapefile.

| File | Rows/features | Columns and role | Bytes |
| --- | ---: | --- | ---: |
| [inputs/voter-counts.csv](inputs/voter-counts.csv) | 47 | `county_name`, `county`, `vtd`, `race`, `party`, `n`: aggregate counts for the 16 joint cells and their margins | 1,622 |
| [inputs/block-groups.geojson](inputs/block-groups.geojson) | 5 | `GEOID`, `pop`, `area`, the nine covariates below, and geometry: match keys, population weights, land-area totals, and covariates | 105,117 |
| [inputs/precincts.geojson](inputs/precincts.geojson) | 6 | `vtd`, `county_nam`, `fips`, and geometry: precinct match targets and the final geometry dataset | 114,443 |

The nine covariates are `med_age`, `med_inc`, `edu_coll`, `edu_hsless`,
`edu_prof`, `edu_somecoll`, `pop_dens`, `city_dist`, and `white_pov`.
`GEOID`, `pop`, and `area` are necessary intermediate fields: they identify
block groups, weight covariates, and produce `pop_total`/`area_total` in the final
table. The data contain no names, addresses, voter IDs, or unused source attributes.
See the [codebook](../../codebook.qmd) for units and definitions; in particular,
`med_inc` is already logged and `city_dist` is in meters.

GitHub [renders CSV tables and GeoJSON maps](https://docs.github.com/en/repositories/working-with-files/using-files/working-with-non-code-files).
Both GeoJSON files use WGS84 longitude/latitude, rounded to seven decimal places,
with all source vertices retained. The runner restores the source coordinate
systems before matching. Undefined numeric values are encoded as JSON `null`.
The county's output geometry is simplified on its own, so its retained display
vertices can differ from a subset of a statewide simplification.

## Results and memory

Results go to [release/tyrrell/](../../release/README.md), which remains ignored:

- `nc_vtd_wide.csv`: six rows and the full 40-column final schema.
- `nc_vtd_geo.rds` and `nc_vtd_geo.geojson`: six simplified precinct geometries,
  with only `vtd`, `county_nam`, and `fips` attributes.

The CSV writes missing covariates as blank fields and zero counts as `0`.
See the [release README](../../release/README.md) for importing blanks as `NA`
and preserving identifier columns as character strings.

Measured locally on macOS with R, sf 1.1-1, and geomander 2.5.3:

| Measure | Footprint |
| --- | ---: |
| Three input files, before Git compression | 221,182 bytes (216 KiB) |
| Loaded input R objects | 162,720 bytes (159 KiB) |
| Combined output R objects | 23,784 bytes (23 KiB) |
| Three generated output files | 12,334 bytes (12 KiB) |
| Peak R process resident memory, including packages and temporary allocations | 427,327,488 bytes (408 MiB) |
| Elapsed example run, excluding installation | 2.79 seconds |

The runner prints file and object sizes. Peak process memory was measured with
Python's `resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss` after running
`Rscript examples/tyrrell/run.R` in a fresh subprocess (bytes on macOS).
Object sizes are not peak RAM requirements; platform and package versions will
change memory use and runtime. Budget roughly **0.5 GB RAM** for this small run
on a comparable setup. This is not a measurement of the full statewide build.

The resulting table was compared with the saved Tyrrell reference: counts and
column types agree, and all numeric covariates agree within `1e-12`. The
[regression check](../../tests/test-tyrrell.R) locks the spatial assignments,
precinct totals, and missing-covariate behavior without downloads.

## Provenance and refreshing the example

The initial counts and covariates were extracted from the retained legacy
`ei-practical/prepare/data/nc_vf_agg.rds` and `nc_bg_cov.rds`; the latter already
contains ACS estimates and city/university distances. SBE geometry comes from
the locally verified 2025-02-25 bundle, and full 2024 TIGER block groups were
retrieved with `tigris`. The [full input manifest](../../manifests/inputs.yml)
documents the voter snapshot, SBE bundle, university points, and Census vintages.
The separate example hashes lock the exported subset; they do not replace the
full-input checksums or validate a complete fresh Census-backed build.

Replicators do not need to refresh these files. To rebuild the frozen inputs,
maintainers should first run the [full pipeline](../../run.R), following
[data/raw/README.md](../../data/raw/README.md), then run:

```sh
Rscript examples/tyrrell/build-inputs.R
```

[build-inputs.R](build-inputs.R) reads the configured intermediates and raw SBE
bundle, downloads the required TIGER boundaries, selects the documented columns,
and rewrites the three inputs and their manifest. It also requires `tigris`.
An optional first argument selects another intermediate directory; the initial
extraction used `../prepare/data`. That path is recorded only as provenance and
is never read by the example runner. Review the data and hash changes together,
rerun the example and regression check, and update the measured sizes if needed.
