# Intermediate Data

The pipeline writes these rebuildable stage outputs here. Files are ignored by
Git; only this README is tracked. A replicator starts with this directory empty
apart from the README and supplies the inputs described in
[data/raw/README.md](../raw/README.md).

| Generated file | Role | Written by | Used by |
| --- | --- | --- | --- |
| `nc_vf_agg.rds` | Precinct race-by-party voter counts after recoding | [01](../../prepare/01_nc-vf-fmt.R) | [04](../../prepare/04_nc-wide_combine.R) |
| `r1_coords.rds` | Validated copy of the supplied university point table | [02a](../../prepare/02a_nc-universities.R) | [02b](../../prepare/02b_distances.R) |
| `cities_dist.rds` | Minimum block-group distance to a selected city or R1 university, in meters | [02b](../../prepare/02b_distances.R) | [02](../../prepare/02_nc-acs_covs.R) |
| `nc_bg_cov.rds` | ACS block-group covariates, land area, and distances | [02](../../prepare/02_nc-acs_covs.R) | [03](../../prepare/03_nc-geomatch.R) |
| `nc_vtd_cov.rds` | Covariates aggregated to SBE precinct identifiers | [03](../../prepare/03_nc-geomatch.R) | [04](../../prepare/04_nc-wide_combine.R) |
| `nc_vtd_geo.rds` | Simplified SBE geometry with precinct and county identifiers | [03](../../prepare/03_nc-geomatch.R) | [04](../../prepare/04_nc-wide_combine.R) |

No pre-existing ACS block-group dataset, distance table, or voter aggregate
needs to be copied here. [run.R](../../run.R) executes
`00 → 01 → 02a → 02b → 02 → 03 → 04`, using the years and paths in
[config/pipeline.yml](../../config/pipeline.yml). Stages 02b, 02, and 03 retrieve
the required Census data when uncached.

[manifests/inputs.yml](../../manifests/inputs.yml) describes and locks the
supplied inputs. These intermediate files do not have expected hashes in that
manifest. The published products and their planned output hashes are described
in [release/README.md](../../release/README.md) and
[manifests/outputs.yml](../../manifests/outputs.yml). See the
[main README](../../README.md) for verification and build commands.
