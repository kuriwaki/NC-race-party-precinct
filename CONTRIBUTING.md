# Contributing

This repository is currently a design draft. PRs can clarify the plan, document
provenance, improve the examples, or propose small reviewed mapping changes.
Production pipeline code will follow after the input/version choices settle.

## Keep data local

Put source data under `data/raw/`, intermediates under `data/intermediate/`,
and deliverables under `release/`. These directories are ignored. Never
force-add L2 records, NC voter records, shapefiles, extracts, or Census caches.
Do not include individual voter examples, addresses, credentials, or raw-record
logs in PRs. Use invented rows for examples and aggregate diagnostics.

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
including files added with `git add -f`. This guard is not implemented yet.

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

Eventually, public PR checks will run small invented-data examples, syntax and
manifest checks, and data-exclusion checks. Full data validation will compare
local outputs with the reference build using the same reviewed inputs and
dependency versions. No complete pipeline or test suite is claimed at this stage.
