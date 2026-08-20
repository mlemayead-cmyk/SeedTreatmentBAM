# Project state and restart guide

Last saved: 2026-08-20 09:20 -04:00 (America/Toronto)

## What this project is

`stbam` — an R reimplementation of the calculation engine behind a
thiamethoxam seed-treatment bird-and-mammal risk assessment, intended to
support regulatory review. Built per the master instructions in
`.venv/projectInstructions.txt` in the sibling document-review project
(`C:\MonDossierMartin\Python_Local\Python_Document analysis`).

## Current phase: recovery and independent audit (not yet complete)

A prior session built most of the engine, tests, reporting layer, and
Shiny dashboard, then ran out of credit before documentation, version
control, or independent validation existed. This session's job — **not yet
finished** — is to recover that state safely, make it testable by a human
reviewer, and independently audit it before any further feature work.
Explicit instruction from the reviewer: **do not substantially expand
scientific functionality until the independent audit is complete.**

## What was true BEFORE this session (inherited, not built today)

- Full calculation engine (`R/calculations/`), input/parameter layer
  (`R/inputs/`), canonical dataset builders (`R/summaries/`), reporting
  layer (`R/reporting/`), and Shiny dashboard (`R/shiny/`, `app/app.R`) —
  all implemented.
- `docs/scientific_model_specification.md` — complete, rigorous, with
  workbook-cell citations.
- 9 test files, later confirmed to pass in full (see below).
- `data/reference/*.csv` — extracted from 6 source calculation workbooks
  plus 4 registers copied from the review project.
- No git repository. No README, no other docs. No `dependencies.lock.json`.
  The Shiny app had never been manually launched by a human.

## Work completed THIS session, in order

1. **Diagnosed the prior session's stopping point.** Ran the full test
   suite correctly (an initial attempt under-loaded the `shiny` R layer and
   produced spurious failures; corrected) — confirmed **424 assertions, 0
   failures** across all 9 test files.
2. **Ran the canonical CSV/XLSX build** (`scripts/build_canonical_outputs.R`)
   — completes in ~22s — and discovered it then hangs attempting Word
   export of the `risk_and_duration` table (8,928 rows). Measured the
   scaling (100 rows: 4.2s; 800 rows: 59.0s, superlinear) and ruled out
   `flextable`'s `autofit` setting as the cause (fixed-width layout was
   only marginally faster). Diagnosis recorded in
   `docs/word_export_diagnosis.md` — **not yet fixed**, per explicit
   instruction to diagnose before redesigning.
3. **Set up git.** Created `.gitignore` (excludes `.Rproj.user/`,
   `outputs/` [~24MB, regenerable], Python `__pycache__/`; added
   `.gitkeep` placeholders for `reports/`, `data/scenarios/`,
   `data/processed/`, `templates/`). Initialized the repo, made baseline
   commit `ae68620` ("Baseline: pre-independent-audit recovered
   implementation"), added remote `origin` =
   `https://github.com/mlemayead-cmyk/SeedTreatmentBAM.git`, and pushed to
   `main` — authentication was already valid, push succeeded without
   intervention.
4. **Verified the Shiny app actually launches.** `Test-NetConnection`
   alone was insufficient (port opens immediately but the app takes ~8-10s
   to serve content); confirmed with `curl.exe` (HTTP 200 in 8.7s — normal
   bslib/multi-module cold-start, not a hang). Note: PowerShell's
   `Invoke-WebRequest` timed out against this same working server twice in
   this environment for reasons unrelated to the app — use `curl.exe` or a
   real browser to check Shiny responsiveness here, not
   `Invoke-WebRequest`.
5. **Read every file under `R/`** (all 5 calculation files, both input
   files, all 5 summary files, all 3 shiny module files, `app/app.R`) to
   write accurate documentation and to prepare an independent
   understanding of the engine prior to auditing it.
6. **Launched an independent adversarial numerical audit** as a separate
   agent process with no prior exposure to this engine's code, working from
   the specification, raw reference data, and the audited source workbook
   only. **Status: running as of this save; not yet complete.** See
   "Immediate next step" below.
7. **Wrote and verified `scripts/reviewer_validation_walkthrough.R`.**
   First run surfaced a real bug worth recording: the script's own
   hand-calculation variable names (`seeds_per_m2`, `field_rate_g_ai_per_ha`)
   collided with the engine's exported function names of the same
   quantities, and got silently overwritten when the engine was loaded
   later in the same R session. Fixed by snapshotting hand-calculated
   values into a separate `hand` list before loading the engine. Re-run
   confirmed: **11 of 11 quantities agree with the live engine to within
   1e-9 relative difference.**
8. **Wrote the full documentation set** (see below).

## Documents created this session

| File | Status |
|---|---|
| `README.md` | Complete |
| `PROJECT_STATE.md` | Complete (this file) |
| `.gitignore` | Complete |
| `docs/manual_shiny_smoke_test.md` | Complete — ready to use |
| `docs/word_export_diagnosis.md` | Complete — diagnosis only, no fix implemented |
| `docs/model_walkthrough.md` | Complete |
| `scripts/reviewer_validation_walkthrough.R` | Complete and verified (11/11 pass) |
| `docs/manual_acceptance_test.md` | Complete — ready to use |
| `docs/developer_guide.md` | Complete |
| `docs/user_guide.md` | Complete |
| `docs/data_dictionary.md` | Complete |
| `docs/table162_support_methodology.md` | Complete |
| `docs/model_validation_report.md` | Complete but marked **provisional** — its Layer 3 (independent audit) section is a placeholder pending the audit agent's completion |
| `docs/independent_engine_audit.md` | **Pending** — being written by the background audit process |
| `audit/independent_engine_findings.csv` | **Pending** — same |

## Validation status right now

- Automated tests: **PASS**, 424/424, confirmed this session.
- Reviewer walkthrough: **PASS**, 11/11, confirmed this session, bug found
  and fixed in the process.
- Independent adversarial audit: **NOT YET COMPLETE.** Do not treat the
  engine as scientifically validated until this lands and its findings
  (if any require correction) are addressed.
- Manual Shiny testing: **NOT YET PERFORMED** by a human. The app is
  confirmed to launch and serve content; nobody has clicked through it yet.
- Source immutability: not re-verified this session against the original
  Word/workbook SHA-256 baselines (those live in the sibling review
  project, `C:\MonDossierMartin\Python_Local\Python_Document analysis\PROJECT_STATE.md`)
  — this project only reads already-extracted `data/reference/*.csv`
  copies and did not touch any original source file.

## Immediate next step (when this session resumes)

1. **Check whether the independent-audit background agent has completed.**
   If its final message hasn't arrived, it is still running — do not
   re-launch a duplicate. If it has completed, read
   `docs/independent_engine_audit.md` and
   `audit/independent_engine_findings.csv` in full before doing anything
   else.
2. Update `docs/model_validation_report.md`'s Layer 3 section and overall
   verdict to reflect the actual findings.
3. If the audit reports any `CONFIRMED_ERROR` or `POTENTIAL_ERROR`: stop,
   report the findings to the human reviewer, and do **not** silently
   correct the engine without that conversation — per the explicit
   instruction, findings are reported before any fix, and fixes are a
   distinct, deliberate step followed by re-validation.
4. If the audit is clean (all `PASS`/`DOCUMENTATION_GAP`/
   `REQUIRES_HUMAN_REVIEW` with no confirmed numerical error): report that
   to the reviewer, and the recovery/audit phase's completion gate (see
   `.venv/projectInstructions.txt` §18 in the sibling project, or the
   equivalent instruction given directly) is essentially met pending the
   reviewer's own manual acceptance testing.
5. Do not begin the Word-export redesign, any new crop-family work, or any
   other scientific-functionality expansion until the reviewer has
   explicitly signed off on the audit and their own manual testing.

## Git

- Repository: `C:\MonDossierMartin\R\seed_treatment_bam_model` (local),
  `https://github.com/mlemayead-cmyk/SeedTreatmentBAM.git` (`origin`).
- Branch: `main`.
- Baseline commit: `ae68620` — "Baseline: pre-independent-audit recovered
  implementation" — pushed successfully.
- Portable git used: `C:\MonDossierMartin\LNom\PortableGit\bin\git.exe`
  (not on PATH in this environment).
- No commits made after the baseline as of this save. The next commit
  should be the audit findings (docs + findings CSV), kept separate from
  any subsequent corrective commit, per the reviewer's explicit request to
  distinguish audit-driven changes from later feature development.

## Exact restart procedure

From PowerShell in `C:\MonDossierMartin\R\seed_treatment_bam_model`:

```powershell
$rscript = "C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe"
$git = "C:\MonDossierMartin\LNom\PortableGit\bin\git.exe"

# 1. Confirm git state
& $git status
& $git log --oneline -5

# 2. Confirm the environment
& $rscript scripts\check_environment.R

# 3. Re-run the full test suite
& $rscript -e "source('R/load_model.R'); load_stbam('.', include=c('core','reporting','shiny')); testthat::set_max_fails(Inf); testthat::test_dir('tests/testthat', reporter='summary')"

# 4. Re-run the reviewer walkthrough
& $rscript scripts\reviewer_validation_walkthrough.R

# 5. Read this file's "Immediate next step" section above and act on it.
```

Do not begin new scientific functionality, the Word-export redesign, or
another crop workbook without the reviewer's explicit authorization, per
the standing instruction for this recovery phase.

## Stop state

Recovery/audit phase is **in progress, not complete**. Git baseline exists
and is pushed. The Shiny app is confirmed launchable. Core documentation
exists. The independent adversarial audit was launched but its completion
has not yet been confirmed as of this save. **Do not declare this phase
finished until `docs/independent_engine_audit.md` exists, has been read,
and its findings have been reflected in `docs/model_validation_report.md`.**
