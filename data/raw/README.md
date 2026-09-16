# Raw Data

To try the pipeline without these large inputs, run the tracked
[Tyrrell County example](../../examples/tyrrell/README.md).

Place the three supplied input bundles below in this directory. Their contents
are ignored by Git; only this README is tracked. All paths in the `directories`
and `files` lists of [the input manifest](../../manifests/inputs.yml) are relative to this
directory. That manifest records each dataset's description, role, provenance,
consuming scripts, exact byte counts, and SHA-256 hashes.

The configured build requires 108 files, totaling 690,741,150 bytes (about
691 MB). The layout is:

```text
data/raw/
├── README.md
├── ncvoter_2025-08-02/
│   ├── county_name=ALAMANCE/part-0.parquet
│   ├── county_name=ALEXANDER/part-0.parquet
│   ├── ... one partition for each of the 100 NC counties ...
│   ├── county_name=NEW%20HANOVER/part-0.parquet
│   └── county_name=YANCEY/part-0.parquet
├── SBE_PRECINCTS_20250225/
│   ├── SBE_PRECINCTS_20250225.cpg
│   ├── SBE_PRECINCTS_20250225.dbf
│   ├── SBE_PRECINCTS_20250225.prj
│   ├── SBE_PRECINCTS_20250225.sbn
│   ├── SBE_PRECINCTS_20250225.sbx
│   ├── SBE_PRECINCTS_20250225.shp
│   └── SBE_PRECINCTS_20250225.shx
└── r1_universities/
    └── r1_coords.rds
```

## Copying files from another location

1. Locate the provider's August 2025 voter snapshot, February 2025 SBE bundle,
   and original R1 point file. Their parent folders may differ from this layout.
2. Create the three destination folders shown above. Copy the voter dataset
   with its original county partition directories; copy the SBE and R1 files
   into their individual manifest paths. Preserve the original bytes. Copy actual file contents so this
   repository can be moved independently of the provider's folders.
3. Check that the files are directly under the expected roots, without an extra
   wrapper such as `SBE_PRECINCTS_20250225/SBE_PRECINCTS_20250225/`. If a provider
   supplies an archive, extract it elsewhere and copy only the required data.
4. Run the verification command below. No manifest edits are needed for a
   replicator with matching files.

The verifier requires the exact inventory inside each of the three bundle
folders. Keep ZIPs, `.DS_Store`, extra XML files, README files, and other
unlisted members outside those folders. This README lives above the checked
roots and is allowed. A matching filename alone is insufficient: verification
also checks the file size and SHA-256.

## NC voter registration

Use the retained snapshot labeled **2025-08-02**. It contains one
`part-0.parquet` file per county in a Hive-style `county_name=...` directory.
The manifest stores one checksum for the whole voter directory, not 100
individual partition hashes. The checksum includes each relative filename,
byte count, and file content hash in a fixed order.
Do not flatten the directories, rename them, or re-export the Parquet files.
Preserve the literal percent-encoded directory `county_name=NEW%20HANOVER`.
If partitions arrive separately, their original county labels identify the
destination folders; the complete directory checksum then verifies the set.
The 100 county names are included in [R/nc-reference.R](../../R/nc-reference.R).

[Stage 01](../../prepare/01_nc-vf-fmt.R) reads county and precinct identifiers,
race/ethnicity codes, and party registration to build precinct race-by-party
counts. It applies the recodes in
[R/nc-precinct-recodes.R](../../R/nc-precinct-recodes.R).

The retained Parquet is already formatted upstream. Original August 2025
county ZIP/TSV files have not been recovered. A current NCSBE download, the
February 2026 statewide snapshot, or a re-export of the same records is not a
byte-identical replacement for this input.

## SBE precinct boundaries

Use **SBE_PRECINCTS_20250225** and all seven components listed above. The `.shp`
contains geometry, `.dbf` attributes, `.shx` the geometry index, `.prj` the CRS,
`.cpg` the text encoding, and `.sbn`/`.sbx` spatial indexes. The spatial indexes
are retained because the existing manifest locks this seven-file bundle.
Keep the common basename and the original bytes of every component.

[Stage 03](../../prepare/03_nc-geomatch.R) uses these boundaries to assign
block-group covariates to precincts and produce simplified precinct geometry.
Other SBE vintages, Census voting districts, and Gaston KML are not substitutes.

## R1 university points

Copy the original **r1_coords.rds** to `r1_universities/r1_coords.rds`. The locked
file has 147 rows, columns `name`, `state`, and `geometry`, and point geometry
in EPSG:4269. It is 20,248 bytes. Do not read and re-save it, filter to NC, or
transform its CRS when placing the input.

The retained source was `precinct_ticketsplit/data-raw/colleges/r1_coords.rds`.
That path records provenance; the pipeline reads only the copy in this repo.
[Stage 02a](../../prepare/02a_nc-universities.R) validates and writes an
intermediate copy. [Stage 02b](../../prepare/02b_distances.R) combines the full
university table with selected city points to compute block-group distances.

[config/pipeline.yml](../../config/pipeline.yml) sets the file path through
`universities.reviewed_points`. Stage 02a uses this supplied point table;
upstream college geometry, an R1 workbook, and a matching crosswalk are not
part of this build.

## Inputs retrieved or generated by code

These do not need to be supplied or copied into `data/raw/`:

| Input | Role and how it is obtained |
| --- | --- |
| 2023 ACS 5-year tables | [Stage 02](../../prepare/02_nc-acs_covs.R) retrieves B01003 (population), B01002 (median age), B19013 (median income), B15003 (education), and B17001 (poverty) through `easycensus`. Age and income use tract/county fallbacks; White non-Hispanic poverty is measured at county level. |
| 2024 full TIGER block groups | [Stage 02](../../prepare/02_nc-acs_covs.R) downloads land area; [stage 03](../../prepare/03_nc-geomatch.R) downloads the geometry for precinct matching. |
| 2024 cartographic TIGER block groups | [Stage 02b](../../prepare/02b_distances.R) uses `tigris::block_groups(..., cb = TRUE)` for distances. The full and cartographic variants serve different purposes. |
| City points | [Stage 02b](../../prepare/02b_distances.R) reads `ggredist::cities`, selecting 2020 population greater than 100,000 in NC, SC, TN, VA, and GA. |
| County IDs, regions, and precinct recodes | Small reference mappings are included in [R/nc-reference.R](../../R/nc-reference.R) and [R/nc-precinct-recodes.R](../../R/nc-precinct-recodes.R). |

The shared [ACS median helper](../../R/nc-acs.R) applies the block-group → tract
→ county fallback to income and age. Stage 02 uses `easycensus` for retrieval;
stage 03 uses `geomander::geo_match(method = "area")` for spatial matching and
`dplyr` for population-weighted covariate aggregation.

Census retrieval requires network access when responses are not cached. The
input manifest documents the queries and roles but does not yet lock retrieved
ACS/TIGER bytes or package versions. Input-file verification covers the 108
supplied files; it does not establish byte-identical Census responses.

L2 files, saved `nc_bg_cov.rds`, `cities_dist.rds`, voter aggregates, and previous
release files are also unnecessary as supplied inputs. The latter datasets are
rebuilt under [data/intermediate/](../intermediate/README.md) and
[release/](../../release/README.md).

## Verify and build

The voter directory uses `directory_hash_format: sha256-path-bytes-filehash-v1`.
[hash_directory()](../../R/nc-utils.R) lists all files recursively, including
hidden files, and sorts relative paths in radix order. It computes the SHA-256
of UTF-8 records of `relative/path<TAB>bytes<TAB>file-sha256<LF>`, with slash
path separators, decimal byte counts without grouping, and a final newline.
Only the resulting directory hash, total bytes, and file count are recorded in
the manifest. Moving the whole directory leaves this hash unchanged; changing,
renaming, adding, or removing a file changes it. Empty directories are ignored.

Run from the repository root, not from `data/raw/`:

```sh
Rscript prepare/00_nc_download.R
```

[Stage 00](../../prepare/00_nc_download.R) uses
[R/check-inputs.R](../../R/check-inputs.R) and
[manifests/inputs.yml](../../manifests/inputs.yml). A complete matching input
set reports `Verified 108 files against SHA-256.` The check never changes the
expected hashes. If it fails, resolve the reported path, version, or byte
mismatch with the provider before rebuilding.

Then run `Rscript run.R` (or `source("run.R")` in RStudio).
[run.R](../../run.R) executes stages in the order set by
[config/pipeline.yml](../../config/pipeline.yml). See the
[main README](../../README.md) for the build overview and the
[release README](../../release/README.md) for deliverables and output hashes.
