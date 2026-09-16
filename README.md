# NC race, party, and precinct data

This repository builds the NC precinct
datasets from three supplied input bundles plus Census data retrieved by code.


## Getting Started

Try a small county first:

Run `Rscript examples/tyrrell/run.R` from this repository's root. The
[example README](examples/tyrrell/README.md) lists the required packages and explains
the inputs, outputs, and measured memory use. It uses six precincts, five block
groups, and 47 aggregate race-by-party count rows from Tyrrell County. Its three
CSV/GeoJSON inputs total 200Kb and can be previewed on GitHub.
No supplied voter files, Census downloads, or API key are needed to run it.

The example verifies [its own manifest](manifests/example-tyrrell.yml), then runs
the same spatial matching and combination functions as stages 03 and 04.
It writes the wide-table CSV and precinct geometry (RDS/GeoJSON) under
`release/tyrrell/`. These three small outputs are also tracked for inspection
without running R; other release datasets remain ignored. It starts from frozen aggregate counts and block-group
covariates; use the full pipeline below to rebuild those inputs.

For a full run, start with [data/raw/README.md](data/raw/README.md) to place supplied files.
[PLAN.md](PLAN.md) records the original design, output definitions, and remaining
validation work. The reference is the NC preparation pipeline in `ei-practical`,
ending in `prepare/04_nc-wide_combine.R`; this implementation uses paths within
this repository and does not require that checkout.


## Step 0. What exists now

- [.gitignore](.gitignore) excludes local data, common data formats, outputs,
  caches, credentials, and R session files. The READMEs in the data and release
  directories are tracked so those directories exist in a fresh clone.
- [run.R](run.R) runs the stages listed in [config/pipeline.yml](config/pipeline.yml):
  `00 -> 01 -> 02a -> 02b -> 02 -> 03 -> 04`.
- [R/](R/) contains the root-path helpers, strict input checker, county/region
  references, and precinct recode rules.
- [prepare/](prepare/) contains the self-contained NC stage scripts adapted from
  the original `prepare/` pipeline.
- [codebook.qmd](codebook.qmd) documents the output schema, voter universe,
  covariates, source vintages, and geometry ambiguity.
- [R/check-inputs.R](R/check-inputs.R) implements strict SHA-256 verification,
  including missing files and unexpected shapefile components.
- [manifests/inputs.yml](manifests/inputs.yml) is the build manifest. It
  locks 100 voter Parquet partitions, seven SBE shapefile components, and one
  R1 university point file. It describes each dataset's role, provenance,
  consuming scripts, and placement, along with the inputs retrieved by code.
- [CITATION.cff](CITATION.cff) is the preferred citation and lists NCSBE,
  Census ACS/TIGER, and related sources.
- [CONTRIBUTING.md](CONTRIBUTING.md) describes the proposed PR workflow.


## Step 1: More on placing the supplied inputs

All 108 supplied files are covered by
[manifests/inputs.yml](manifests/inputs.yml): one checksum for the complete voter
dataset, plus individual hashes for the SBE components and R1 file. Full-size data remain local and are
excluded from Git. A clone includes a small, runnable [Tyrrell County example](examples/tyrrell/README.md)
with aggregate counts and public boundaries.
The full build and equivalence to the legacy outputs remain to be validated.


Open `NC-race-party-precinct.Rproj` and work from this directory. Obtain the
following retained files from the data provider and copy them to these paths:

| Supplied dataset | Destination relative to this repository | First consuming stage |
| --- | --- | --- |
| August 2, 2025 NC voter snapshot: 100 county Parquet partitions | `data/raw/ncvoter_2025-08-02/county_name=.../part-0.parquet` | [01: voter counts](prepare/01_nc-vf-fmt.R) |
| February 25, 2025 SBE precinct bundle: seven components | `data/raw/SBE_PRECINCTS_20250225/SBE_PRECINCTS_20250225.*` | [03: spatial match](prepare/03_nc-geomatch.R) |
| Original R1 university point table: 147 points | `data/raw/r1_universities/r1_coords.rds` | [02a: university points](prepare/02a_nc-universities.R) |

The provider's files may be in other folders. The `directories[].path` and
`files[].path` entries in [manifests/inputs.yml](manifests/inputs.yml), relative
to `data/raw/`, specify the destinations. Copy the original bytes; do not re-export Parquet, re-save
RDS, or rewrite shapefiles. Follow the component list, partition naming rules,
and copying instructions in [data/raw/README.md](data/raw/README.md).

No L2 files, older precinct bundles, current voter downloads, or saved
intermediates are required. Stage 02 retrieves the 2023 ACS 5-year tables;
stages 02b, 02, and 03 retrieve the required 2024 TIGER block groups. City points
come from `ggredist::cities`. These steps require the relevant R packages and
network access for uncached Census data. Their retrieved bytes are not currently
locked by the input manifest.

## Step 2: Verify the inputs

From the repository root, run the verification stage alone:

```sh
Rscript prepare/00_nc_download.R
```

[Stage 00](prepare/00_nc_download.R) uses
[R/check-inputs.R](R/check-inputs.R) to check all 108 files against the manifest.
It stops on missing files, unexpected files within any of the three input
bundles, size mismatches, or hash mismatches. Successful verification reports
`Verified 108 files against SHA-256.` It does not download replacement files or
change the expected hashes.

The voter directory checksum covers the relative names and bytes of all 100
partitions. Per-partition hashes are computed during verification but are not
listed in the manifest. The format is documented in
[data/raw/README.md](data/raw/README.md).

A different download or re-export can have different bytes even when it appears
to describe the same geography or records. Check the supplied snapshot and
placement first. Replication does not require editing the manifest or removing
pending entries: `pending_roots` is empty for the current supplied inputs.

## Step 3: Run the pipeline

After placing and verifying the inputs, run:

```r
# Written by Codex
source("run.R")
```

Or use `Rscript run.R` from a shell in the repository root. Shared dependencies
(`cli`, `fs`, `glue`, `purrr`, `readr`, `scales`, and `yaml`) are checked by
[R/nc-utils.R](R/nc-utils.R); each stage lists its additional packages near the
top. Manifest validation uses `checkmate`, ACS retrieval uses `easycensus`, and
spatial matching uses `geomander`. [config/pipeline.yml](config/pipeline.yml)
controls input roots, Census years, build order, and destination paths.

| Directory | Contents and instructions |
| --- | --- |
| [data/raw/](data/raw/README.md) | The three supplied, hash-locked input bundles |
| [data/intermediate/](data/intermediate/README.md) | Rebuilt voter counts, university points, distances, covariates, and geometry |
| [data/diagnostics/](data/diagnostics/README.md) | Recode keys and spatial matching summaries |
| [release/](release/README.md) | The wide table and precinct geometry deliverables |

By default, stage 04 writes the output files but does not rewrite
[manifests/outputs.yml](manifests/outputs.yml); a maintainer can set
`outputs.write_manifest: true` in [config/pipeline.yml](config/pipeline.yml)
after reviewing a successful build.

The starting voter data are the retained formatted Parquet snapshot, and the
university data are a frozen upstream point table. This builds from those
snapshots; reconstructing their original ZIP/TSV inputs and university matching
decisions remains separate provenance work, described in the input manifest.

## Deliverables

The overall pipeline publishes:

- CSV: `release/nc_vtd_wide.csv` (precinct race-by-party counts, margins,
  regions, and covariates). Missing values are blank; zeros remain `0`.
- RDS: `release/nc_vtd_geo.rds` (simplified SBE geometry in the reference CRS).
- GeoJSON: `release/nc_vtd_geo.geojson`, the same precinct geometry with
  identifier columns only (`vtd`, `county_nam`, `fips`).
- Codebook: `codebook.qmd`.
- SHA-256 hashes of supplied inputs in [manifests/inputs.yml](manifests/inputs.yml).
  [manifests/outputs.yml](manifests/outputs.yml) will hold release hashes after
  a reviewed successful build.

Cite the dataset and its NCSBE, Census, and other sources with
[CITATION.cff](CITATION.cff).

## Advanced: Focused regression checks

With `testthat` installed, run these checks from the repository root:

```r
# Written by Codex
testthat::test_dir("tests", stop_on_failure = TRUE)
```

[tests/test-pipeline.R](tests/test-pipeline.R) checks the directory-checksum
format, altered inputs, manifest validation, ACS median fallbacks, and precinct
total preservation using temporary files and small in-memory tables.
[tests/test-tyrrell.R](tests/test-tyrrell.R) checks the real example's spatial
assignments, counts, and missing covariates. Both run without supplied data or
network access. `testthat` reports object differences using
`waldo`; integer-count comparisons use zero tolerance. These focused checks do
not replace validation of a full Census-backed build.

Public PRs should contain code, documentation, small reference mappings,
manifests, and the three explicitly allowed Tyrrell example inputs and three
release outputs. Raw data and other generated datasets remain local. `.gitignore` prevents
ordinary accidental additions; it cannot stop `git add -f` or untrack files that
were previously committed. See the planned PR check in [CONTRIBUTING.md](CONTRIBUTING.md).
