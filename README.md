# NC race, party, and precinct data

**Draft implementation for iteration.** The repository now contains the
standalone NC-only stages, config, manifests, and codebook scaffold. The full
build is intentionally blocked until the missing voter-file and R1 university
inputs are added to `manifests/inputs.yml` with reviewed SHA-256 hashes.

The intended pipeline publishes:

- RDS: `release/nc_vtd_wide.rds` (precinct race-by-party counts, margins,
  regions, and covariates) and `release/nc_vtd_geo.rds` (simplified SBE
  geometry in the reference CRS).
- GeoJSON: `release/nc_vtd_geo.geojson`, the same precinct geometry with
  identifier columns only (`vtd`, `county_nam`, `fips`).
- Codebook: `codebook.qmd`.
- SHA-256 hashes of input and output data files in `manifests/`.

Cite the dataset and its NCSBE, Census, and other sources with
[CITATION.cff](CITATION.cff).

Start with [PLAN.md](PLAN.md) for the source inventory, execution order, exact
output definitions, legacy issues, and implementation milestones. The reference
is the NC preparation pipeline in `ei-practical`, ending in
`prepare/04_nc-wide_combine.R`. The eventual build must run entirely from this
repository, without that checkout, saved R workspace objects, or personal paths.

## What exists now

- [.gitignore](.gitignore) excludes local data, common data formats, outputs,
  caches, credentials, and R session files. No source data has been copied here.
- [run.R](run.R) runs the stages listed in [config/pipeline.yml](config/pipeline.yml):
  `00 -> 01 -> 02a -> 02b -> 02 -> 03 -> 04`.
- [R/](R/) contains the root-path helpers, strict input checker, county/region
  references, and precinct recode rules.
- [prepare/](prepare/) contains the self-contained NC stage scripts adapted from
  the original `prepare/` pipeline.
- [codebook.qmd](codebook.qmd) documents the output schema, voter universe,
  covariates, source vintages, and geometry ambiguity.
- [examples/check-inputs.R](examples/check-inputs.R) demonstrates strict SHA-256
  verification, including missing files and unexpected shapefile components.
- [manifests/sbe-20250225.example.yml](manifests/sbe-20250225.example.yml)
  contains measured hashes of the seven locally available SBE components.
  This is a real but **partial** input manifest; it does not certify the voter
  snapshot, ACS, university coordinates, L2, or the full build.
- [manifests/inputs.yml](manifests/inputs.yml) is the build manifest. It
  currently locks the seven SBE shapefile components and marks the voter and R1
  roots as pending.
- [examples/combine-wide.R](examples/combine-wide.R) demonstrates the final
  widening and joins using a small, invented dataset; it does not read voters
  or generate the deliverables.
- [CITATION.cff](CITATION.cff) is the preferred citation and lists NCSBE,
  Census ACS/TIGER, and related sources.
- [CONTRIBUTING.md](CONTRIBUTING.md) describes the proposed PR workflow.

## Run the pipeline

Open `NC-race-party-precinct.Rproj` and work from this directory. Place reviewed
inputs under `data/raw/`, update `manifests/inputs.yml`, and remove the
corresponding `pending_roots` entries. Then run:

```r
# Written by Codex
source("run.R")
```

By default, stage 04 writes the output files but does not rewrite
`manifests/outputs.yml`; set `outputs.write_manifest: true` in
`config/pipeline.yml` after reviewing a successful build.

## Try the examples

The examples use `cli`, `digest`, `dplyr`, `glue`, `purrr`, `scales`, `tibble`,
`tidyr`, and `yaml`; they do not install packages or download data.

Run `Rscript examples/combine-wide.R` for the invented-data example.

To try file verification, place the original seven SBE files under
`data/raw/SBE_PRECINCTS_20250225/`, then run:

```r
# Written by Codex
source("examples/check-inputs.R")
verify_inputs("manifests/sbe-20250225.example.yml")
```

The verifier stops on missing files, unexpected files, size mismatches, or hash
mismatches. It never changes the expected hashes. A different download can have
different bytes even if it appears to represent the same geography; review a
new manifest rather than accepting it automatically.

Public PRs should contain code, documentation, small reference mappings, and
manifests. Raw data and generated datasets remain local. `.gitignore` prevents
ordinary accidental additions; it cannot stop `git add -f` or untrack files that
were previously committed. See the planned PR check in [CONTRIBUTING.md](CONTRIBUTING.md).
