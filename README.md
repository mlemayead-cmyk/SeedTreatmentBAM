# stbam — Bird and Mammal Seed-Treatment Risk Assessment Model

A transparent, testable R reimplementation of the calculation engine behind
a pesticide (thiamethoxam) seed-treatment risk assessment for birds and
mammals, intended to support regulatory review. It reproduces the audited
Excel workbook's calculations, makes every equation and assumption
explicit and inspectable, and adds an editable-parameter interface,
time-dependent exposure modelling, and structured decision-support output
for Table 162 of the source assessment.

**Current status (2026-08-20): recovery/audit phase, not yet released.**
The calculation engine, canonical datasets, table/CSV/Word reporting layer
and Shiny dashboard are implemented and pass an internal automated test
suite (424 assertions). An **independent adversarial numerical audit is the
current gating step** before any of this is relied on scientifically — see
`docs/independent_engine_audit.md` and `PROJECT_STATE.md` for its status.
Read `PROJECT_STATE.md` before doing anything else in this project.

## What this is not

This model calculates. It does not decide. Table 162 acceptability
positions, peer-review consensus, and their rationale are human-controlled
fields that the software never populates (see
`docs/table162_support_methodology.md`).

## Quick start

```powershell
# 1. Confirm the environment
"C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" scripts\check_environment.R

# 2. Run the automated test suite
"C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" -e "source('R/load_model.R'); load_stbam('.', include=c('core','reporting','shiny')); testthat::test_dir('tests/testthat')"

# 3. Walk through one scenario by hand and compare with the engine
"C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" scripts\reviewer_validation_walkthrough.R

# 4. Launch the dashboard
"C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" scripts\run_app.R
# then open http://127.0.0.1:8080

# 5. Generate the priority self-contained exposure/risk figures (no Shiny)
"C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" scripts\generate_priority_exposure_figures.R
```

See `docs/manual_shiny_smoke_test.md` for a guided first look at the
dashboard, and `docs/developer_guide.md` for the full command reference.
See `docs/priority_exposure_figures.md` for static-figure coverage, grouping,
calculation definitions and output locations.

## Documentation map

Read in roughly this order:

1. **`PROJECT_STATE.md`** — current status, what's validated vs. merely
   implemented, exact restart procedure. Read this first, every session.
2. **`docs/scientific_model_specification.md`** — the formal model
   contract: every equation, unit, source citation, and stated limitation.
3. **`docs/model_walkthrough.md`** — the same material, narrated in plain
   language with one worked example carried all the way through.
4. **`docs/independent_engine_audit.md`** — an adversarial, independent
   re-derivation of the calculations, checking the engine rather than
   trusting it.
5. **`docs/manual_shiny_smoke_test.md`** then **`docs/manual_acceptance_test.md`**
   — guided manual testing of the dashboard.
6. **`docs/user_guide.md`** — how to use the dashboard.
7. **`docs/developer_guide.md`** — architecture, how to run/build/test,
   dependency management.
8. **`docs/data_dictionary.md`** — every reference table and canonical
   dataset column.
9. **`docs/table162_support_methodology.md`** — how the model's output
   connects to the source assessment's Table 162 decisions.
10. **`docs/word_export_diagnosis.md`** — why large Word exports currently
    hang, and the proposed fix (not yet implemented).
11. **`docs/model_validation_report.md`** — consolidated validation status
    across the automated tests, the reviewer walkthrough, and the
    independent audit.

## Relationship to the source review project

This project reads (read-only) selected outputs from a separate document
and workbook review project at
`C:\MonDossierMartin\Python_Local\Python_Document analysis` — the source
Word assessment documents, the audited calculation workbooks, and that
project's structural/traceability review registers. See
`data/reference/source_manifest.csv` and `copied_register_manifest.csv` for
exact provenance and SHA-256 hashes. Nothing in this project modifies those
source files.

## License / confidentiality

Internal working project. Not for external distribution.
