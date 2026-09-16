# Diagnostics

The pipeline writes local recode and spatial matching diagnostics here. These
files are ignored by Git; only this README is tracked. A replicator does not
need to supply any files in this directory.

| File | Purpose | Producing script |
| --- | --- | --- |
| `stage01_precinct_recode_keys.rds` | Distinct county and precinct identifiers used to inspect voter-file recoding | [01: voter counts](../../prepare/01_nc-vf-fmt.R) |
| `stage01_unknown_codes.rds` | County, race, or party codes that cause stage 01 to stop; written only if encountered | [01: voter counts](../../prepare/01_nc-vf-fmt.R) |
| `stage03_match_coverage.rds` | Counts of block groups, SBE features, distinct precinct keys, and matched precinct keys | [03: spatial match](../../prepare/03_nc-geomatch.R) |

These are generated reports, not supplied inputs or release datasets, so they
are outside the [input manifest](../../manifests/inputs.yml) and
[output manifest](../../manifests/outputs.yml). Their destination is set in
[config/pipeline.yml](../../config/pipeline.yml); [run.R](../../run.R) runs the
producing stages. See the [main README](../../README.md) for build instructions
and the [codebook](../../codebook.qmd) for the geometry coverage ambiguity.
