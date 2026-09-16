# Release

[Stage 04](../prepare/04_nc-wide_combine.R) writes the published datasets here.
Data files are ignored by Git; only this README is tracked. No pre-existing
release files need to be supplied to reproduce the build.

The offline [Tyrrell example](../examples/tyrrell/README.md) writes the same
wide-table CSV and geometry RDS/GeoJSON under `tyrrell/` here.
Those generated files are also ignored; the small example inputs live under
`examples/tyrrell/inputs/` and have [their own manifest](../manifests/example-tyrrell.yml).

| File | Contents and role |
| --- | --- |
| `nc_vtd_wide.csv` | One row per precinct, with 16 race-by-party counts, margins, county/region identifiers, and demographic covariates |
| `nc_vtd_geo.rds` | Simplified SBE precinct geometry with `vtd`, `county_nam`, and `fips`, retaining the source CRS |
| `nc_vtd_geo.geojson` | The same geometry and identifiers in WGS84 longitude/latitude for GIS use |

The wide CSV and geometry RDS are the core datasets. GeoJSON is another representation of
the geometry dataset. The geometry can contain multiple rows per precinct key;
see [codebook.qmd](../codebook.qmd) for definitions, units, and coverage notes.

CSV missing values are blank fields (`readr::write_csv(..., na = "")`). A blank
means missing or unavailable; a count of zero is written as `0`. Empty strings
are not meaningful values in this schema. CSV does not store R column types,
so import `county` and `vtd` as character identifiers:

```r
# Written by Codex
wide <- readr::read_csv(
  "release/nc_vtd_wide.csv", na = "",
  col_types = readr::cols(county = readr::col_character(), vtd = readr::col_character())
)
```

For the example, use `release/tyrrell/nc_vtd_wide.csv` instead.

Place the supplied inputs according to [data/raw/README.md](../data/raw/README.md),
verify them against [manifests/inputs.yml](../manifests/inputs.yml), and run
[run.R](../run.R) from the repository root. It rebuilds the required
[intermediates](../data/intermediate/README.md) and runs stage 04. Paths and
build options are set in [config/pipeline.yml](../config/pipeline.yml).

[manifests/outputs.yml](../manifests/outputs.yml) is reserved for the byte counts
and SHA-256 hashes of these three release files. It is currently empty because
the full build has not yet been reviewed. A maintainer can enable
`outputs.write_manifest: true` in the pipeline config after reviewing a build;
stage 04 then writes the output manifest using
[R/nc-utils.R](../R/nc-utils.R). Input verification never updates expected hashes.

See the [main README](../README.md) for commands and
[CONTRIBUTING.md](../CONTRIBUTING.md) for source and manifest changes.
