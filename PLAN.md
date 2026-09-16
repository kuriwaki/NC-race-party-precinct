# Standalone NC pipeline: implementation plan

Status: proposed design with examples. No production stages, full input lock,
dependency lockfile, or CI workflow have been implemented. All paths below are
relative to this repository unless explicitly identified as legacy provenance.

## 1. Scope and compatibility target

Reconstruct the datasets written by the original
`prepare/04_nc-wide_combine.R`: the wide precinct table and the simplified SBE
geometry. Its two writes of the wide table are copies of the same dataset. The
geometry is built upstream and merely copied by stage 04. This repository will
write each data file once under `release/`, plus a tracked codebook.

Use the current NC preparation rules as the first compatibility target. Keep
model fitting, paper figures, non-NC analyses, the survey crosswalk export, and
exploratory L2/Wake mapping outside the core build. `seine` is not used by these
data-construction stages, so it is not a required dependency. If a later example
adds EI fitting, use the latest `CoryMcCartan/seine` at that time and record its
resolved Git commit in comments and the dependency lockfile.

Local inspection of the saved reference outputs found:

| Property | Observed value |
| --- | --- |
| Wide table | 2,465 rows, 40 columns, unique `vtd` |
| Geometry table | 2,655 rows, 4 columns, 2,465 distinct `vtd` |
| Geometry rows beyond one per key | 190 |
| Wide precincts absent from geometry | 0 |
| Wide precincts absent from the covariate table | 86 |
| Geometry CRS label | NAD83 / North Carolina (ftUS) |

These are observations of existing artifacts, not proof that today's source
scripts reproduce them. Record reference hashes and compare a future rebuild
before calling it equivalent. Do not drop unmatched covariate rows to make
assertions pass.

The geometry table has more rows than unique `vtd` keys (2,655 vs 2,465), and
a stage-03 comment says 2,652 SBE features. Treat that mismatch as an
**unresolved ambiguity**: duplicate features, true multipart geometry stored as
separate rows, or a vintage/comment discrepancy are all possible. This plan
does not choose whether to dissolve, keep the extra rows, or otherwise
reconcile the counts. Document the observed numbers in the codebook and join
diagnostics; a wide-to-geometry join may be one-to-many until a later review
decides otherwise.

## 2. Inputs and unresolved provenance

| Input | Version used by the source code | Acquisition and hash plan |
| --- | --- | --- |
| NC voter registration | Snapshot labeled `2025-08-02`, stored as county-partitioned Parquet | Recover the original county ZIP/TSV snapshots and record their acquisition dates and hashes. The retained Parquet is already formatted and cannot alone establish a raw rebuild. Hash every partition if retaining it as a migration reference. |
| SBE precinct geometry | `SBE_PRECINCTS_20250225` | Record the original ZIP hash when available, plus hashes for every extracted component. Seven existing components are covered by the example manifest. |
| ACS | 2023 ACS estimates queried through `easycensus` | Explicitly fix the ACS product used by the existing helper (expected ACS 5-year; confirm locally when implementing), tables, geography, and state. Archive and hash the exact retrieved responses; do not silently accept a revised response. |
| TIGER block groups | 2024 full geometry for area/matching; 2024 cartographic geometry (`cb = TRUE`) for distances | Retain both variants, archive the downloaded files and every shapefile component, and record the query options. These variants are not interchangeable. |
| County FIPS | NC entries of `tigris::fips_codes`; legacy stage 00 also has an explicit named vector | Make a reviewed 100-county reference table with character FIPS, full names, and explicit SBE download IDs. Do not infer a download ID from incidental row ordering. |
| Cities | `ggredist::cities`, `pop_2020 > 100000`, in NC, SC, TN, VA, GA | Pin package version/source and hash a local extracted input; preserve the 2020 population threshold. |
| R1 university locations | Legacy `~/Dropbox/precinct_ticketsplit/data-raw/colleges/r1_coords.rds` | Bring its source recipe and upstream inputs into the proposed stage 02a; resolve the missing inputs before a raw rebuild. |
| County regions | `prepare/NC-counties/nc-regions.R` | Copy the 100-row mapping into a small reviewed R reference file. Its current header says it came from an LLM; label it as a project mapping pending source review. |
| L2 voter data | `VM2Uniform--NC--2025-10-03.tab` | Not consumed by stages 00–04. Keep optional and local; hash the licensed original and any extract separately if that branch is later requested. Both `*.tab` files and the data directory are already ignored. |

The February 26, 2026 statewide NC voter ZIP/TSV, 2022/2023 SBE files, 2022 NC
geography, Gaston KML, and 2024 election-history/statistics files are not selected
inputs for the current core pipeline. Do not substitute them based on availability.

The old county downloader constructs an SBE URL from a county index. That is a
moving endpoint, not an archive of August 2025. A current download is a new data
version. If the original raw voter snapshot cannot be recovered, distinguish a
build from the retained formatted snapshot from a genuinely raw rebuild and
document the resulting limitation.

### Recover the university source recipe

The external `R/prepare/R1_universities.R` reads
`wikipedia_R1.xlsx` and `us-colleges-and-universities@public` geometry. It filters
degree-granting institutions by NAICS description, `hi_offer` in 11/12, and
`inst_size` in 2:5, then fuzzy-matches uppercased institution names within state.
It keeps the largest similarity per institution and transforms to EPSG:4269.

The local `r1_coords.rds` and spreadsheet currently have zero-byte sizes; they
cannot be treated as valid inputs. Recover usable copies and their original
source/version metadata. Replace stochastic fuzzy matching with a reviewed,
small identifier crosswalk, or pin the original implementation and resolve
ties explicitly. Verify equivalent institution coverage and distances before
accepting the replacement. The legacy distance script filters cities to five
states but appends the university table without a state filter; preserve that
behavior initially. No nearest-centroid substitution: the source measures
minimum distance from block-group geometry to the city/university points.

## 3. Proposed repository layout

```text
README.md, PLAN.md, CONTRIBUTING.md
CITATION.cff                       # dataset citation and NCSBE/Census sources
codebook.qmd                       # variable definitions, units, vintages
NC-race-party-precinct.Rproj
.gitignore
config/pipeline.yml                 # selected snapshots and build options
manifests/inputs.yml                # reviewed SHA-256 values and provenance
manifests/outputs.yml               # SHA-256 of published data files
R/check-inputs.R                    # promote the example after review
R/nc-reference.R                   # county IDs and region lookup
R/nc-precinct-recodes.R             # small, documented recode tables
prepare/00_nc_download.R
prepare/01_nc-vf-fmt.R
prepare/02a_nc-universities.R
prepare/02b_distances.R
prepare/02_nc-acs_covs.R
prepare/03_nc-geomatch.R
prepare/04_nc-wide_combine.R
run.R                              # explicit stage order, clean-session build
renv.lock                          # create once dependencies are settled
examples/                          # current draft code, invented data only
data/raw/                          # ignored, immutable acquired inputs
data/intermediate/                 # ignored, rebuildable stage outputs
release/                           # ignored: rds and geojson deliverables
data/diagnostics/                   # ignored, join and count summaries
cache/, logs/                      # ignored
```

[CITATION.cff](CITATION.cff) is the preferred citation for this dataset and
attributes the North Carolina State Board of Elections, Census ACS and TIGER
files, and other inputs. Keep it in sync with the codebook vintages when those
settle.

Keep the familiar script names and short RStudio section headers. Each script
declares its inputs, outputs, snapshot assumptions, and any substantive recodes
near the top. Use explicit namespaces or libraries, new object names for each
transformation, `readr::read_rds()`/`write_rds()`, `glue::glue()`, `scales`
formatters, and `cli` alerts/progress with their built-in success/warning/info
icons. Every new script starts with `# Written by Codex`.

Resolve all paths from this project's root; set both the RStudio and CLI entry
points explicitly. Do not depend on an enclosing project's `here()` root or
objects left in an interactive session. Keep Census credentials in ignored
`.Renviron`, with credential names documented separately. Record R, package,
GDAL/GEOS/PROJ, s2, and mapshaper versions/settings with each local build.

## 4. Stage order and transformations

The legacy numbering is not execution order: distances must precede ACS.
The proposed driver runs **00 → 01 → 02a → 02b → 02 → 03 → 04**. It verifies
each stage's selected raw inputs before use. A local build should be able to
reuse verified downloads and run without network access.

| Stage | Adapt from | Work and local products |
| --- | --- | --- |
| 00: acquire/verify | `prepare/00_nc_download.R` | Fetch selected public inputs or explain manual placement; verify archives before extraction and components afterward. Separate acquisition from formatting. Produce immutable raw inputs. |
| 01: voter counts | `prepare/01_nc-vf-fmt.R`, race/party mapping in 00 | Read raw records with declared types, format race/party, apply the exact exclusions and precinct recodes, then count to `data/intermediate/nc_vf_agg.rds`. |
| 02a: universities | External recipe described above | Rebuild the point table from pinned institutional sources and a reviewed crosswalk, writing `r1_coords.rds` locally. |
| 02b: distances | `prepare/02b_distances.R` | Assemble cities/universities, explicitly align CRS/units, compute minimum geometry-to-point distance, write `cities_dist.rds` in meters. |
| 02: covariates | `prepare/02_nc-acs_covs.R` | Construct block-group population, area, age, income, education, density, distance, and county White poverty; write `nc_bg_cov.rds`. |
| 03: spatial match | `prepare/03_nc-geomatch.R` | Apply SBE ID corrections, assign each full block group to the precinct with maximum area overlap, aggregate covariates, simplify geometry, and write `nc_vtd_cov.rds` and intermediate geometry. |
| 04: combine | `prepare/04_nc-wide_combine.R`, region mapping | Pivot the 16 joint cells, compute margins, join covariates and regions, and write the published outputs in §5. |

### Voter definitions to preserve

- Hispanic ethnicity (`ethnic_code == "HL"`) takes precedence over race.
  White = W; Black = B; Other = A/I/M/O/P. Keep the four levels
  `white`, `black`, `hisp`, `other` in this order.
- DEM → `dem`, UNA → `ind`, REP → `rep`, LIB → `lib`; all other or missing
  party codes currently fall back to `ind`. Document that `ind` therefore
  includes more than unaffiliated registrants.
- Retain the current filter `race_code != "U"`, `ethnic_code != "UN"`, and
  nonmissing `vtd_abbrv`. R's filter also excludes missing race/ethnicity.
  Do not add an active-registration or turnout filter: none appears in stage 01.
  Report unexpected race codes and empty precinct identifiers for review.
- Start with character county FIPS + `precinct_abbrv`; switch to `vtd_abbrv`
  for Gaston, Wake, Harnett, Pender, and Columbus. Preserve the ordered special
  cases for Rockingham, Duplin, Vance, Harnett, Columbus, Henderson, Pender,
  Union, and Transylvania, then collapse Wake suffixes at the first dash.
- Migrate the literal rules before reorganizing them. Several rules refer to
  the updated `vtd`; flattening them into an unordered lookup can change results.
  Keep original identifiers and rule IDs in local diagnostics, and compare
  county/race/party totals before and after recoding.

### Covariates and spatial rules to preserve

- Population: B01003. Land area: 2024 TIGER `ALAND / 1609.34^2`, square miles.
- Median income: B19013, total population; fill missing block-group estimates
  from tract then county and log **before** precinct aggregation.
- Median age: B01002, total race/ethnicity and sex; same tract/county fallback.
- Education: B15003, population age 25+; proportions for professional/graduate,
  bachelor's, some college/associate's, and high school or less.
- County poverty: B17001, White alone non-Hispanic, total age/sex; share below
  poverty, attached to each block group in the county.
- Density: block-group population divided by land area. The precinct value is
  its population-weighted mean, not `pop_total / area_total`.
- Match full 2024 block groups to corrected SBE features using
  `geomander::geo_match(..., method = "area")`. Record unmatched groups and
  review ties; do not silently replace this with fractional allocation.
- Aggregate covariates with `weighted.mean(x, pop)` and sum population/area.
  Preserve current missing-value propagation (no automatic `na.rm = TRUE`).
  A precinct with no assigned block group retains missing covariates.
- Apply the Haywood/Gaston geometry recodes and Wake suffix rule from stage 03.
  Simplify with `rmapshaper::ms_simplify(keep = 0.04, keep_shapes = TRUE)`.
  Match the source feature order/settings for compatibility. Leave extra
  geometry rows as they are in this pass; resolving the row-count ambiguity
  in §1 is out of scope.

All tabular joins declare `relationship`. Most covariate joins are
`many-to-one`; the final unique precinct table joins unique covariates
`one-to-one`. Spatial matching has no dplyr `relationship` argument, so inspect
its mapping cardinality explicitly. Use key coverage checks as well: join
cardinality alone does not detect missing keys.

## 5. Output contract

The published products are (1) RDS files, (2) a GeoJSON of the precinct
geometry with identifiers, (3) a Quarto codebook, and SHA-256 hashes of the
input and output data files. Data files go under `release/` and remain
gitignored. `codebook.qmd` and the YAML manifests are tracked.

### RDS

`nc_vtd_wide.rds` is a non-spatial table with one row per `vtd`. Keep identifiers
as character strings to retain leading zeros. Preserve these names and ordering:

```text
county_name, county, nc_region_4, vtd, total,
white_, black_, hisp_, other_, _rep, _dem, _ind, _lib,
white_dem, white_ind, white_rep, white_lib,
black_dem, black_ind, black_rep, black_lib,
hisp_dem, hisp_ind, hisp_rep, hisp_lib,
other_dem, other_ind, other_rep, other_lib,
med_age, med_inc, edu_coll, edu_hsless, edu_prof, edu_somecoll,
pop_dens, city_dist, white_pov, pop_total, area_total
```

`total` and all margins are counts, not proportions. Calculate them from the
16 named cells only, never from every numeric column. `med_inc` is the
population-weighted mean of logged block-group median incomes; `med_age` is a
weighted mean of block-group medians. `city_dist` is meters; `pop_dens` is people
per square mile; `area_total` is square miles; education and poverty are shares.

`nc_vtd_geo.rds` is an `sf` object with `vtd`, `county_nam`, `fips`, and
`geometry`, preserving the reference CRS (NAD83 / North Carolina, ftUS). Its
keys should cover the wide table. Geometry row counts need not equal unique
precincts; see §1.

### GeoJSON (geometry and IDs)

Write `nc_vtd_geo.geojson` from the same geometry object, keeping only the
identifier columns `vtd`, `county_nam`, and `fips` plus `geometry`. Do not
attach the wide-table counts or covariates. Transform to CRS84 (WGS84
longitude/latitude) for RFC 7946 GeoJSON; the RDS copy keeps the reference
State Plane CRS. Record both CRSs in the codebook.

### Codebook

`codebook.qmd` is the human-readable data dictionary. It should define every
wide-table column (meaning, type, units, missingness), the geometry ID fields
and CRS, the voter-file universe and race/party recodes, ACS/TIGER vintages,
and the input/output hash manifests to consult. Note the geometry row-count
ambiguity from §1 without resolving it.

### Hashes

`manifests/inputs.yml` and `manifests/outputs.yml` record SHA-256 values for
every required input file and every published data file (`*.rds`, `*.geojson`).
The codebook is tracked in git and does not need a data-manifest hash. Hash
rules are in §6.

The combine example illustrates the count contract with invented values. It
deliberately leaves one precinct without covariates to show retention and a
`cli` warning. It does not implement the full covariate schema or geometry.

## 6. Hash verification and reproducibility

Use tracked YAML manifests so that the data-format ignore rules do not hide
the checksums. `manifests/inputs.yml` covers required source files;
`manifests/outputs.yml` covers the published RDS and GeoJSON files. Record a
dataset ID, source version, acquisition method/date when known, relative path,
byte count, and lowercase SHA-256 for every required file.
Use `digest::digest(file = path, algo = "sha256", serialize = FALSE)`; large
files are hashed from disk without loading them as an R dataset.

For shapefiles, verify the complete bundle, not only `.shp`. For partitioned
Parquet, list every partition and compare the actual file inventory with the
manifest, so added partitions cannot enter silently. Treat archives and their
extracted members as separate artifacts. Exclude only explicitly documented
non-input metadata; do not silently accept extra files in a dataset's scope.

The example manifest's hashes were measured from the existing local SBE files.
They establish byte identity with those files, not independent authenticity,
download dates, or scientific correctness. Do not invent checksums for missing
raw voter files, API responses, or university inputs. L2 needs its own optional
manifest group; a core build should not require it. Do not invent output hashes
until those files exist.

Verification must fail before processing when a required input is absent,
empty, changed, unexpectedly added, or has no reviewed hash. After a
successful build, compare published outputs to `manifests/outputs.yml` the same
way. Explain which relative file failed using `cli`. Never refresh expected
hashes inside the verification/build command. A separate maintainer operation
may propose a new manifest; review the source, vintage, transformation
implications, and manifest diff in a PR before using it as the baseline.

Archive exact API responses and package-supplied reference data locally and
lock their hashes after review. RDS bytes, GeoJSON coordinate rounding, and
geometry simplification can change across software versions, so treat output
hashes as the byte-identity check and compare semantic content separately:
sorted keys, counts, missingness, covariates with stated numerical tolerances,
geometry coverage, CRS, and area.

## 7. Known issues to resolve when porting

1. Stage 00 returns `voters`, although its constructed object is `voters_fmt`;
   its snapshot-writing line is commented out. Fix the return and implement
   explicit raw acquisition; sourcing the legacy script is not a raw rebuild.
2. Its temporary ZIP path uses `paste()` with a space. Use `file.path()` and
   local cleanup. County source IDs must be explicit and checked.
3. Stage 02b assumes libraries/objects from an interactive session and reads a
   different repository. Stage 04 calls `here()` without loading it itself.
   Give every stage declared inputs and libraries.
4. Replace joins lacking `relationship` and transformations that overwrite
   their source object. Preserve computational definitions while doing so.
5. Replace stage 04's broad numeric sum with an explicit 16-cell sum, and
   explicitly expand all four race and party levels before pivoting.
6. Replace stage 03's abbreviated `compress = "x"` with `compress = "xz"`.
7. Review the source comment questioning Harnett counts and the Vance NH1/NH2
   recodes. Retain their legacy behavior until a documented correction is
   accepted; report changes separately from the mechanical port.

The 2,652 vs 2,655 vs 2,465 row counts are the geometry ambiguity in §1, not a
porting bug to fix in this plan.

## 8. Iteration milestones

1. Review this plan, confirm the historical snapshot target, and recover raw
   voter/university sources. Complete the input inventory and reviewed hashes.
2. Copy only the required NC scripts and small reference mappings; make the
   acquisition and university stages self-contained. Add `cli` progress and
   explicit run order. Freeze dependencies after the first successful build.
3. Compare the new outputs with the saved reference: exact integer cells and
   margins, county totals, 86 unmatched covariate keys, geometry key coverage,
   CRS, and documented numeric/geometry tolerances. Investigate differences.
   Record SHA-256 values for the published RDS and GeoJSON files. Note any
   geometry row-count mismatch; do not treat resolving it as a requirement of
   this milestone.
4. Add a small invented-data PR smoke check and a tracked-file size/type check.
   Write `codebook.qmd`. Full licensed/historical data builds remain a
   maintainer operation. No private inputs or credentials should be required
   by public fork PRs.

Do not build a full test suite in this drafting pass. The checks that will
matter most are raw file identity, total preservation through recodes, correct
join cardinality/coverage, valid race-party margins, and output hashes.
