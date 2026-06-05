# Manual Migrations

This folder contains SQL that is applied **manually** (with `psql`), separately from the
graphile-migrate flow in `migrations/committed/`. These are optional add-ons to the core ISO 28258
schema: run them after the base schema is in place (`yarn gm migrate`, or by loading a release dump
from `releases/`).

## Spectral Extension

The `spectral_extension/` folder adds spectral data support to the ISO 28258 schema for the
Specimen feature of interest: raw spectra (stored as JSONB) and physico-chemical results derived
from spectra via calibration models.

> **Status:** Work in progress. This is a working version of the spectral extension and still needs
> to be validated by domain experts before production use.

- `spectral_extension.sql` - tables, validation trigger and ETL functions (all in the `core` schema)
- `docs/readme.md` - documentation with ER diagrams and usage examples

It creates nine `core.*` tables (`sensor`, `procedure_spectral`, `observation_spectral`,
`result_spectral_specimen`, `calibration_set`, `calibration_set_result_specimen`, `model_spectral`,
`observation_spectral_derived_specimen`, `result_spectral_derived_specimen`) and depends only on
existing base objects: `core.specimen`, `core.unit_of_measure`, `core.observation_phys_chem_specimen`,
`core.result_phys_chem_specimen`, `metadata.individual` and `metadata.organisation`.

The script is idempotent (`CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE`), so it is safe to run
more than once. It is project-agnostic - no role names are hardcoded; add `GRANT` statements in your
own project if needed.

To apply, either run it with `psql`:

```bash
psql -d <database_name> -f migrations/manual/spectral_extension/spectral_extension.sql
```

or via graphile-migrate's `run` command (runs against `DATABASE_URL`; `--shadow` / `--root`
available):

```bash
yarn gm run migrations/manual/spectral_extension/spectral_extension.sql
```

Once applied, the v1.9 bridge functions detect it automatically via
`core.bridge_has_spectral_extension()`.
