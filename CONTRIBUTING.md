# Contributing

This repository contains a draft standalone implementation. PRs can improve
the pipeline, document provenance, or propose small reviewed mapping changes.
The full build and equivalence to the legacy outputs remain to be validated.

## Keep data local

Put source data under `data/raw/`, intermediates under `data/intermediate/`,
and deliverables under `release/`. Their READMEs and the three small
[Tyrrell release files](release/README.md) are tracked. Follow
[data/raw/README.md](data/raw/README.md) for the exact input placement and
[config/pipeline.yml](config/pipeline.yml) for paths and build order. Never
force-add L2 records, NC voter records, shapefiles, extracts, or Census caches.
Do not include individual voter examples, addresses, credentials, or raw-record
logs in PRs. The three [Tyrrell example inputs](examples/tyrrell/README.md) are
explicit exceptions: aggregate counts and public CSV/GeoJSON data with only
the fields needed by the pipeline. Other examples should use invented rows or
aggregate diagnostics.

Track manifests as YAML under `manifests/`, the codebook as `codebook.qmd`,
citation and source attribution as `CITATION.cff`, and small reviewed mappings
as R source under `R/`. If a future reference table needs another format, add a
narrow, reviewed `.gitignore` exception for that exact file.

Before staging or committing, inspect `git status --short` and
`git ls-files -ci --exclude-standard`. The second command identifies tracked
files that now match ignore rules; an ignore file does not untrack existing
data. Review `git diff --cached --stat` and the staged diff. Do not commit on
another contributor's behalf.

Planned CI will reject tracked data directories, prohibited raw/binary formats,
and unexpectedly large files (initial proposal: 1 MiB per tracked file, with
explicit reviewed exceptions). It will check the full tracked inventory,
including files added with `git add -f`, and allow the three exact input paths in
[manifests/example-tyrrell.yml](manifests/example-tyrrell.yml) and the three exact
Tyrrell release paths in [.gitignore](.gitignore). This guard is not implemented yet.

## Code and source updates

Use native pipes, tidy data, `summarize()`, explicit `relationship` in tabular
joins, `glue::glue()`, `scales` number formatting, and `readr` RDS I/O. Give each
transformation a fresh object name. Start new scripts with `# Written by Codex`
and use `# Section name ----` / `## Subsection name ----` headers. Use `cli`
alerts and progress, with relative paths and aggregate counts in messages.

Explain what each stage reads, writes, and assumes. For precinct rules, identify
the county, old and new IDs, applicable snapshot, reason/source, and aggregate
impact. Resolve multiple matches rather than weakening join checks.

A source-version change should propose manifest changes separately from hash
verification. Include the source/version and expected output impact; hashes
should never be updated merely to silence a failure. An unreviewed hash proves
only consistency with the file that generated it.

[manifests/inputs.yml](manifests/inputs.yml) uses a single directory checksum for
the voter snapshot and individual hashes for SBE components and the R1 point
file. Keep partition hashes out of the YAML. The directory format and algorithm
are documented in [data/raw/README.md](data/raw/README.md) and implemented in
[R/nc-utils.R](R/nc-utils.R). [Stage 00](prepare/00_nc_download.R) verifies this
manifest before [run.R](run.R) proceeds with the build.

Run `testthat::test_dir("tests", stop_on_failure = TRUE)` from
the repository root for the [focused regression checks](tests/test-pipeline.R).
They cover checksum integrity, malformed manifests, ACS fallbacks, and count
preservation without source data or network access. The
[Tyrrell regression check](tests/test-tyrrell.R) also covers the reviewed spatial
assignments and missing covariates in the real county example. Use `expect_equal()` with
zero tolerance for count tables and `waldo::compare()` when inspecting a
before/after difference; preserve column types as well as values.

Public CI and data-exclusion checks remain future work. Full data validation
must compare local outputs with the reference build using the same reviewed
inputs and dependency versions.
