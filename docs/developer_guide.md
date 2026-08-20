# Developer guide

## Architecture

This is a **source tree, not an installed R package**, deliberately — it
runs in an environment with no package-build toolchain and no CRAN access
(see "Dependency management" below). Everything is loaded by sourcing files
in a fixed order via `R/load_model.R`.

```
R/
  calculations/   Pure calculation functions. No I/O, no side effects.
                   00_validation.R    input-checking helpers, shared constants
                   01_seed_parameters.R   seed mass/TKW/seeding-rate/treatment-loading conversions
                   02_surface_seed.R      surface-seed disappearance + residue dissipation (two SEPARATE processes)
                   03_receptor.R          food intake (Nagy regressions), seeds required
                   04_exposure_risk.R     EDE, dose over time, RQ, duration above metric
                   05_feasibility.R       MSA diagnostics (never touches dose/RQ)
  inputs/         Reference-data loading and the parameter-set/override layer.
                   10_reference_data.R    reads data/reference/*.csv into an stbam_baseline
                   11_parameter_set.R     baseline + override layer; provenance-tagged overrides
  summaries/      Canonical dataset builders (specification section 11).
                   20_scenario_inputs.R   scenario_inputs
                   21_receptor_exposure.R receptor/effects-metric resolution, exposure grid
                   22_daily_timecourse.R  daily_timecourse
                   23_scenario_summary.R  scenario_summary (closed-form, no day loop)
                   24_table162_support.R  table162_support
  reporting/      Everything downstream of the canonical datasets.
                   30_plots.R             ggplot2 plot functions
                   31_tables.R            official-table builders (STBAM_TABLES registry)
                   32_word_export.R       officer/flextable Word export
                   33_data_export.R       CSV/XLSX export
  shiny/          The dashboard. Contains NO scientific calculation of its own.
                   40_modules_inputs.R    scenario selection, parameter editing, override register
                   41_modules_results.R   overview, timecourse, feasibility, comparison, tables, Table 162
                   42_module_sensitivity.R  one-at-a-time sensitivity sweeps
                   43_app.R               stbam_ui(), stbam_server(), run_stbam_app()
  load_model.R    Sources everything above in the right order.
```

**Data flow (one direction only):**

```
data/reference/*.csv  (immutable assessment baseline)
        |
load_baseline() -> stbam_baseline
        |
parameter_set() + set_override()  -> stbam_parameter_set (baseline + override layer)
        |
build_scenario_inputs() -> build_scenario_summary() / build_daily_timecourse()
        |                            |
        |                   build_table162_support()
        v                            v
   plots, tables, Word/CSV/XLSX export, Shiny dashboard
```

Every consumer (Shiny, CSV export, Word export) reads from the same
canonical dataset via the same builder function — e.g.
`build_official_table()` is the single entry point used by the Shiny
"Official tables" tab, the CSV download, and every Word export. This is
enforced by construction, not by convention: there is no second
implementation of any table anywhere in the codebase.

## Running things

All commands assume PowerShell from the project root
(`C:\MonDossierMartin\R\seed_treatment_bam_model`) and R 4.4.3 at
`C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe` (not on PATH in this
environment — use the full path, or add it to your session's PATH).

```powershell
$rscript = "C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe"

# Environment check (packages + versions against dependencies.lock.json)
& $rscript scripts\check_environment.R

# Regenerate the lock file after an intentional package upgrade
& $rscript scripts\check_environment.R --write

# Full test suite (424 assertions across 9 files)
& $rscript -e "source('R/load_model.R'); load_stbam('.', include=c('core','reporting','shiny')); testthat::set_max_fails(Inf); testthat::test_dir('tests/testthat', reporter='summary')"

# Reviewer validation walkthrough (one scenario, by-hand vs. engine)
& $rscript scripts\reviewer_validation_walkthrough.R

# Canonical outputs (CSV/XLSX only take ~22s; do not run the Word-heavy
# path until docs/word_export_diagnosis.md's redesign is implemented —
# see that document before running the full script unmodified)
& $rscript scripts\build_canonical_outputs.R small_cereals

# Launch the dashboard
& $rscript scripts\run_app.R          # port 8080
& $rscript scripts\run_app.R 8090     # custom port
```

**A note on `tests/testthat.R`:** this file uses `sys.frame(1)` to locate
the project root, which only works when the file is *sourced* from within
an existing R session (e.g. `devtools::test()` or `R CMD check`), not when
passed directly to `Rscript`. Running `Rscript tests/testthat.R` directly
fails with `Error in sys.frame(1): not that many frames on the stack`. Use
the explicit `source(...); load_stbam(...); testthat::test_dir(...)` form
above instead, or open the project in RStudio and use its test-running
UI/keyboard shortcut.

## Extending the model

- **New crop:** add a row to `data/reference/crop_seeding_parameters.csv`
  and, if it has a registered rate, to `scenario_definitions.csv`. No R
  code changes needed — `build_scenario_inputs()` reads these tables
  directly.
- **New calculation:** add a pure function to the appropriate file in
  `R/calculations/`, following the existing pattern: explicit arguments and
  units in the roxygen comment, `check_numeric()`/`check_choice()`/
  `check_recyclable()` validation at the top, no hidden defaults, and a
  corresponding `tests/testthat/test-0N-*.R` entry — ideally including at
  least one assertion against a raw workbook cell or an independently
  computed value, not only against the function's own prior output.
- **New official table:** add an entry to `STBAM_TABLES` in
  `R/reporting/31_tables.R`. It becomes automatically available in Shiny's
  "Official tables" tab, the CSV export, and Word export — no separate
  wiring needed. Read `docs/word_export_diagnosis.md` before assuming any
  new table is automatically Word-appropriate; check its expected row count
  first.
- **New Shiny view:** add a module (`mod_x_ui()` / `mod_x_server()`) to
  `R/shiny/`, wire it into `stbam_ui()`/`stbam_server()` in `43_app.R`. The
  module must read from the shared `results()` reactive (see `43_app.R`) —
  never recompute scenario_inputs/scenario_summary independently, or a view
  can silently go stale relative to the rest of the dashboard.

## Dependency management: why there is no `renv.lock`

CRAN is unreachable from this machine. `renv` itself requires bootstrapping
from CRAN (or a local repository mirror it doesn't have), so it cannot be
installed here — this was confirmed, not assumed; do not spend time
re-attempting an `renv::init()` without first confirming CRAN access has
changed.

`scripts/check_environment.R` is the substitute. It:

1. Confirms every required package (see the `REQUIRED` vector in that
   script) is installed.
2. Records the exact installed version of each into
   `dependencies.lock.json` (via `--write`).
3. On every subsequent run, compares the current environment against that
   lock file and reports `ok` / `DIFFERS` / `not in lock file` per package,
   exiting non-zero on any mismatch.

This gives the same practical guarantee `renv.lock` would (a reproducible,
version-pinned environment definition you can diff against), just without
`renv`'s isolated-library mechanism — packages here are installed into the
ordinary user library, not a project-local one. **If CRAN access becomes
available later**, migrating to `renv::init()` +
`renv::snapshot()` is straightforward and would add the isolated-library
benefit; it is not required for reproducibility as currently defined, only
for isolation from other projects' package versions on this machine.

Required packages (see `scripts/check_environment.R` for the authoritative
list): `readr`, `dplyr`, `tibble`, `tidyr`, `rlang`, `vctrs` (engine);
`ggplot2`, `scales`, `officer`, `flextable`, `writexl`, `svglite`,
`rmarkdown`, `knitr`, `digest` (reporting); `shiny`, `bslib`, `DT`,
`htmltools` (interface); `testthat`, `withr` (testing). All were already
installed on this machine as of 2026-08-20; none required a fresh install
during the recovery session.

## Git

This project is a git repository (`origin` =
`https://github.com/mlemayead-cmyk/SeedTreatmentBAM.git`, branch `main`).
See `PROJECT_STATE.md` for the current commit and what it represents.
`outputs/` (generated canonical results, ~24 MB) and `.Rproj.user/`
(RStudio local state) are gitignored — regenerate `outputs/` with
`scripts/build_canonical_outputs.R` rather than expecting it to be present
after a fresh clone.

## Things that are deliberately NOT here yet

- A Quarto/R Markdown reporting layer (specification §17) — not started.
- Sensitivity analysis beyond the one-at-a-time sweep already in the
  Shiny "Sensitivity" tab.
- Any crop-family grouping for Word tables — see
  `docs/word_export_diagnosis.md`.
- `docs/model_validation_report.md`'s independent-audit section, pending
  completion of `docs/independent_engine_audit.md`.
