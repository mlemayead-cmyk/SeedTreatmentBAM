# Model validation report

**Status as of 2026-08-20: independent audit in progress.** This report
will be updated when `docs/independent_engine_audit.md` is complete. Until
then, treat "validated" below as meaning "internally self-consistent and
matches its own specification's cited examples" — not yet "independently
confirmed by a process that didn't also write the code."

## Layer 1: automated test suite

`tests/testthat/` — 9 files, 424 assertions, 0 failures (confirmed
2026-08-20, this recovery session, after correctly loading all three
engine layers — an earlier same-session run under-loaded the `shiny` layer
and produced spurious "function not found" errors; re-run with all three
layers loaded and it is a clean pass).

| File | Assertions | Covers |
|---|---:|---|
| `test-01-unit-conversions.R` | 23 | Seed mass/TKW, seeding-rate conversions, treatment loading, field rate — several assertions pinned to exact audited workbook cells (Q4, R4, F4, G4, H4, I4, W4, X4) at 1e-9 to 1e-12 tolerance |
| `test-02-dissipation.R` | 33 | First-order decline, surface-seed vs. residue separation, combined half-life |
| `test-03-exposure-risk.R` | 43 | EDE (both forms), dose over time, RQ, duration above metric |
| `test-04-feasibility.R` | 25 | MSA diagnostics, including exact workbook crop-sheet cell reproduction |
| `test-05-boundaries-and-errors.R` | 52 | Input validation, edge cases, error messages |
| `test-06-invariants.R` | 25 | Monotonicity and scientific invariants (specification §15) |
| `test-07-scenario-builders.R` | 97 | `scenario_inputs` construction, exact workbook-value reproduction for Barley |
| `test-08-tables-exports.R` | 89 | Official table builders, CSV/XLSX/Word export, Table 162 human-field guard |
| `test-09-shiny.R` | 37 | Reactive server logic (`shiny::testServer`), sensitivity sweep |

These tests were written by the same effort that wrote the engine. They are
necessary but not sufficient evidence — see Layer 3.

## Layer 2: reviewer validation walkthrough

`scripts/reviewer_validation_walkthrough.R` — one worked scenario (Barley,
300 mg a.i./kg seed, broadcast, small bird), calculated by hand in base R
arithmetic from raw reference-data values, then compared against the live
engine. Run and confirmed 2026-08-20: **11 of 11 quantities agree with the
engine to within 1e-9 relative difference** (one at 1.17e-16, i.e.
floating-point noise; the rest exact). See the script's own inline
cross-checks against the specification's cited workbook values.

This is a spot-check and teaching tool, not a systematic audit — it
deliberately covers one scenario in depth rather than many scenarios
shallowly.

## Layer 3: independent adversarial audit

**In progress as of 2026-08-20.** A separate review process (not the effort
that wrote the engine or this report) is independently re-deriving results
for a representative set of scenarios and edge cases, from the
specification and raw reference/workbook data only, before consulting the
engine's own source code. It specifically targets:

- The independent 2x2 agronomic bound grid and its deliberately asymmetric
  TKW pairing (specification §4.1-4.2).
- Isolation of the screening clothianidin conversion from the refined
  exposure chain (specification §9.7).
- Non-interference of MSA/feasibility outputs with regulatory dose/RQ
  (specification §10.3).
- Separation of the two dissipation half-lives (specification §7).
- A unit-error sweep (kg/g/mg, ha/m2, %/fraction, dry/fresh mass).
- Numeric invariants and edge cases (zero rate, zero diet fraction, doubled
  concentration, DT50 = Inf, hidden coupling between crops).

Results will be recorded in `docs/independent_engine_audit.md` and
`audit/independent_engine_findings.csv`, with findings classified `PASS`,
`CONFIRMED_ERROR`, `POTENTIAL_ERROR`, `ROBUSTNESS_ISSUE`,
`DOCUMENTATION_GAP`, or `REQUIRES_HUMAN_REVIEW`. **This report's overall
verdict (final section) is deferred until that file exists.**

## Layer 4: manual acceptance testing

Not yet performed. `docs/manual_shiny_smoke_test.md` and
`docs/manual_acceptance_test.md` are ready for you to work through; results
should be appended here once complete.

## Crop coverage and what is and is not validated

| Crop group | Registered scenarios | Validation status |
|---|---|---|
| `small_cereals` | Yes | `PRIMARY_AUDITED_REFERENCE` — the source workbook received 1,115 independent numeric checks in the prior review project (Phase 3A workbook QA/QC), and this model's engine reproduces named cells from it exactly (Layers 1-2 above) |
| `small_cereals_msa` | Yes | `SCENARIO_SOURCE` only — not independently numeric-audited at the workbook level |
| `canola`, `cucurbits`, `legumes_deep`, `legumes_shallow` | Yes | `SCENARIO_SOURCE` only — the calculation *engine* is the same tested code as Small Cereals (same functions, different input data), but the *source workbook data itself* for these five has not received the same cell-by-cell independent audit Small Cereals did |
| Corn, Sunflower, Sugar Beet, and 80 other crops in `crop_seeding_parameters.csv` | No | No registered application rate exists in `scenario_definitions.csv`; cannot be modelled for exposure at all (agronomic parameters only) |

**Do not present a Canola, Cucurbits, or Legumes result with the same
confidence as a Small Cereals result.** The calculation logic has identical
test coverage; the underlying source numbers for those five workbooks have
not had the same independent verification.

## Overall verdict

**Deferred pending Layer 3.** Provisional statement: the calculation engine
is internally consistent, passes its own test suite, and reproduces a
hand-worked example to machine precision. It has not yet been confirmed by
a process that didn't also write it. Do not rely on this model's output for
any regulatory purpose until this report is updated with a completed Layer
3 and, ideally, a completed Layer 4.
