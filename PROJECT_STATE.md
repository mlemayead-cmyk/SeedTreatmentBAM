# Project state and restart guide

Last saved: 2026-08-20 13:40 -04:00 (America/Toronto)

## Current phase: maximum-obtainable-exposure feature — implemented, independently reviewed, findings corrected

**Read this section first if you are resuming after the recovery/audit
phase below.** After that phase completed, a focused new feature was
added: a "maximum obtainable exposure" analysis distinguishing the
conventional conditional RQ from an availability-constrained
maximum-obtainable RQ, with its own Shiny tab, canonical dataset columns,
figure metadata/self-contained export, and tests. See
`docs/scientific_model_specification.md` §10.4 and
`docs/model_walkthrough.md` §10 for what it calculates;
`docs/model_validation_report.md`'s "Feature addition" section for full
status.

**This feature was built by two concurrent AI sessions working in the
same working tree, not on separate branches** — this session ("Claude")
and a separate session the user ran in parallel ("Codex"), which
independently extended/rewrote some of the same files, most notably
contributing an exact closed-form solution for the maximum-obtainable
RQ's LOC-crossing day (`duration_above_max_obtainable_rq()`, verified
independently and confirmed correct — see the review below) and its own
process-explanation and dietary-fraction plotting functions. **This is
now reflected in git history as multiple interleaved commits under one
identity** (`9706dec`, `8b8b42f`, `a425908`, plus this session's own
subsequent commits) rather than one commit per session. The user
explicitly confirmed pushing the combined history as-is; it is on
`origin/main`.

**Independent adversarial review of this specific feature is complete**
(`docs/max_obtainable_exposure_review.md`): 19 items checked, 8 PASS, 3
CONFIRMED_ERROR (all fixed), 2 POTENTIAL_ERROR (both addressed), 4
ROBUSTNESS_ISSUE (partially addressed), 3 DOCUMENTATION_GAP, 1
REQUIRES_HUMAN_REVIEW. The calculation itself (double-counting, MSA
policy, food-requirement cap, units) passed outright; every defect found
was in reporting (a footnote or sidebar stating the wrong number, always
for mammal/`SURFACE_PLUS_BURIED` receptors) or input robustness, not in
the arithmetic. Full detail and the one remaining item needing your own
scientific judgement (whether mammals should be modelled as accessing
100% of sown/buried seed, inherited from pre-existing `ASSUMPTION-020`
but now driving a headline number rather than a diagnostic flag) are in
`docs/model_validation_report.md`'s "Feature addition" section — read
that before relying on a mammal maximum-obtainable figure for anything
consequential. Bird figures have no open finding.

**Priority bird figure batch complete.** The full assessment-default run of
`scripts/generate_priority_exposure_figures.R` completed on 2026-08-20 in
14.8 minutes. It produced 20,064 summary rows for 836 unique canonical
scenarios x 3 bird receptors x 8 bird effects metrics, selected 72 actual
agronomic-envelope rows, and exported 288 logical figures as 288 PNG plus
288 SVG files. Every one of the 576 manifest entries was independently
checked for existence, byte count and SHA-256; all passed. Representative
main, process and assumed-dietary-fraction figures from all three crop groups
were visually checked and were readable and unclipped. Generated artifacts
are under `outputs/figures/` (gitignored); interpretation is summarized in
`docs/priority_exposure_figures.md` and the generated
`outputs/figures/README_priority_figures.md`.

## What this project is

`stbam` — an R reimplementation of the calculation engine behind a
thiamethoxam seed-treatment bird-and-mammal risk assessment, intended to
support regulatory review. Built per the master instructions in
`.venv/projectInstructions.txt` in the sibling document-review project
(`C:\MonDossierMartin\Python_Local\Python_Document analysis`).

## Current phase: recovery and independent audit — COMPLETE

A prior session built most of the engine, tests, reporting layer, and
Shiny dashboard, then ran out of credit before documentation, version
control, or independent validation existed. This session recovered that
state, made it testable by a human reviewer, ran an independent
adversarial audit, and corrected every finding the audit made that was
within engineering scope to correct. **The recovery/audit phase's own
completion gate (see the reviewer's instruction, section 18) is met**:
git baseline exists, Shiny launches and is documented for manual testing,
the Word-export issue is diagnosed, the independent audit is complete and
its findings addressed, tests pass after correction, and full
documentation exists. **What remains is the reviewer's own manual
acceptance testing (Layer 4) — not yet performed by a human** — and a
short list of recommended-but-optional follow-ups. See
`docs/model_validation_report.md` for the full verdict.

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
| `docs/model_validation_report.md` | Complete — Layer 3 filled in with the actual audit results and a final overall verdict |
| `docs/independent_engine_audit.md` | Complete — written by the independent audit process, reviewed in full |
| `audit/independent_engine_findings.csv` | Complete — 100 rows, reviewed and spot-checked against the markdown report |

## Validation status right now

- Automated tests: **PASS**, 448/448 (424 pre-existing + 24 new regression
  assertions added this session for the audit-driven fixes below).
- Reviewer walkthrough: **PASS**, 11/11, confirmed both before and after
  the code fixes below.
- Independent adversarial audit: **COMPLETE.** 100 items checked, 89
  `PASS`, 0 `CONFIRMED_ERROR`, 0 `POTENTIAL_ERROR`, 6 `DOCUMENTATION_GAP`
  (all corrected in the specification), 4 `ROBUSTNESS_ISSUE` (3 corrected
  in code, 1 documented as intentional), 1 `REQUIRES_HUMAN_REVIEW` (a
  defect in the source workbook itself, referred to the assessment team,
  not something this project resolves). Full detail:
  `docs/independent_engine_audit.md`,
  `audit/independent_engine_findings.csv`,
  `docs/model_validation_report.md`.
- Manual Shiny testing: **NOT YET PERFORMED** by a human. The app is
  confirmed to launch and serve content; nobody has clicked through it yet.
  This is the one remaining gate before this model should be relied on.
- Source immutability: not re-verified this session against the original
  Word/workbook SHA-256 baselines (those live in the sibling review
  project, `C:\MonDossierMartin\Python_Local\Python_Document analysis\PROJECT_STATE.md`)
  — this project only reads already-extracted `data/reference/*.csv`
  copies and did not touch any original source file. The independent
  audit separately re-verified the primary audited workbook's own hash
  unchanged before and after its own reading.

## Audit findings and corrections made this session (after the audit completed)

**The audit's own most important finding (AUD-027): the code was right and
the specification was wrong.** Specification §4.2 described a
one-dimensional seeding-rate bound; the engine (correctly) implements a
full 2×2 grid matching the audited workbook's `Seeding Assumptions!J:M`
block. No dose, RQ, or feasibility output is affected — only raw seed-count
columns. **Fixed by correcting the specification, not the code** (spec
v1.1.0; see its change-control log). Any regulatory table drawn from
`scenario_inputs` must show `seed_mass_bound` alongside
`seeding_rate_bound`.

**Three of four robustness defects fixed in code, with new regression
tests (24 new assertions):**

1. `diet_fraction = 0` crashed `build_scenario_summary()` — fixed in
   `R/calculations/05_feasibility.R` (`days_diet_fraction_feasible()` now
   treats a zero target as trivially feasible, returning `Inf`, rather than
   rejecting it).
2. `clear_override(params, parameter)` always errored with its documented
   default `scope = NULL` — fixed in `R/inputs/11_parameter_set.R`
   (explicit full-length scope-match vector instead of a expression that
   collapsed to zero length).
3. A `seeds_per_ha` override left `seeding_rate_kg_per_ha` and
   `field_rate_g_ai_per_ha` stale, silently violating the row's own
   round-trip identity — fixed in `R/summaries/20_scenario_inputs.R` (mass
   rate now recomputes from the effective seed count when only the seed
   count is overridden, mirroring the existing body-weight → food-intake
   propagation pattern).
4. A global-scope dissipation-half-life override silently rewrites every
   crop — this is the intended fallback behaviour of `effective_value()`,
   not a bug; **documented, not changed**, in `docs/user_guide.md`.

**Six documentation gaps, all corrected in
`docs/scientific_model_specification.md`** (§4.1 citation, §4.2 full
rewrite, §5.4 note on two extra non-workbook field-rate cells, §9.7
rounding note, §10.1 buried-seed decline clock, §13 acceptance-criterion
wording) — see the specification's own change-control table (v1.1.0) for
the complete list.

**One item referred to the assessment team, not something to fix here
(AUD-031):** the audited source workbook itself reports two different
"low bound" surface seed densities on the same buckwheat crop sheet for
mass-supplied crops. This is a defect in the source document. The engine
consistently follows one convention (the one its own feasibility
calculations use); which convention the assessment intends is a scientific
judgement outside this project's scope.

**One open process gap, not yet closed (AUD-099):** the 28-check fixture
set named in specification §13 as an acceptance criterion is not read by
any code. The specification wording has been corrected to state the
criterion properly (compare against an exact recomputation, not the
fixture's own rounded stored value), but the automated check itself is not
yet implemented. Recommended as a near-term follow-up, not a blocker to
the current recovery phase's completion.

**A stray process was also found and stopped this session:** an
`Rscript scripts\build_canonical_outputs.R` run launched earlier in this
same session (to reproduce the Word-export hang for diagnosis) had been
running for roughly 1.5 hours, stuck on the same hang, and was never
terminated at the time. It was force-killed once discovered. No output
files or project state were affected — this was purely a hung, orphaned
process. If a `Rscript.exe` process is found running for an implausibly
long time in a future session, check whether it is a similarly stranded
Word-export attempt before assuming it is doing useful work.

## Immediate next step (when this session resumes)

1. **The reviewer should work through `docs/manual_shiny_smoke_test.md`
   and `docs/manual_acceptance_test.md`.** This is the one remaining gate
   — everything else in the recovery/audit phase is complete.
2. Recommended near-term follow-ups (not blockers, not yet authorized to
   start without the reviewer's go-ahead):
   - Implement the automated fixture-driven acceptance check (AUD-099).
   - Redesign Word table export per `docs/word_export_diagnosis.md` (still
     un-implemented; the diagnosis was deliberately kept separate from any
     fix).
   - Decide whether to warn interactively in Shiny when a global-scope
     override is about to be set (AUD-093), beyond the documentation
     added this session.
   - Consider whether independent numeric audit of the five
     `SCENARIO_SOURCE`-only crop workbooks (canola, cucurbits, both
     legumes workbooks, small_cereals_msa) is warranted before relying on
     their output with the same confidence as Small Cereals.
3. Do not begin any of the above, or any other scientific-functionality
   expansion, without the reviewer's explicit authorization — the standing
   instruction for this recovery phase was not to expand functionality
   before the audit completed, and now that it has, the natural next
   conversation is with the reviewer about priority, not an autonomous
   continuation.

## Git

- Repository: `C:\MonDossierMartin\R\seed_treatment_bam_model` (local),
  `https://github.com/mlemayead-cmyk/SeedTreatmentBAM.git` (`origin`).
- Branch: `main`.
- Baseline commit: `ae68620` — "Baseline: pre-independent-audit recovered
  implementation."
- Second commit: `1558352` — recovery-phase documentation (README,
  user/developer guides, data dictionary, walkthroughs, Word-export
  diagnosis) — no engine code touched.
- Third commit (this save): the independent audit's two output files, the
  three code fixes it drove, their regression tests, and the
  documentation corrections (specification, data dictionary, user guide) —
  see `git log` for its exact hash and full message, which restates this
  summary. Kept as one commit rather than split further, since the audit
  findings and their corrections are one coherent unit of work reported
  together; the baseline (`ae68620`) remains the clean pre-audit reference
  point if a before/after diff is ever needed.
- Portable git used: `C:\MonDossierMartin\LNom\PortableGit\bin\git.exe`
  (not on PATH in this environment).

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

**Recovery/audit phase is complete.** Git baseline exists and is pushed
(plus a documentation commit and, pending, an audit-and-corrections
commit — see "Git" above; check `git log` on resume to confirm the latest
commit matches this file's description). The Shiny app is confirmed
launchable. Core documentation exists and is current.
`docs/independent_engine_audit.md` exists, has been read in full, its
findings CSV cross-checked, and every finding within engineering scope has
been corrected (documentation) or fixed with regression tests (code). The
test suite passes (448/448) and the reviewer walkthrough agrees (11/11)
after the fixes. **STOP. Do not begin new scientific functionality, the
Word-export redesign, or the AUD-099 fixture-check implementation without
the reviewer's explicit authorization.** The only outstanding item before
this model should be relied on is the reviewer's own manual acceptance
testing (Layer 4), which only the reviewer can perform.
