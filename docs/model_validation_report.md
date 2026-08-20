# Model validation report

**Status as of 2026-08-20: core engine independently audited and clean
(see Layer 3). A new feature (maximum obtainable exposure, §"Feature
addition" below) has since been added and is undergoing its own
independent review, not yet complete.** Treat the core engine's
"validated" as meaning independently confirmed by a process that did not
write the code; treat the new feature as implemented and self-tested only
until its own review lands.

## Layer 1: automated test suite

`tests/testthat/` — 11 files, **556 assertions, 0 failures** (confirmed
2026-08-20). 424 predate this session's recovery work; a further 24 were
added for the three engine robustness fixes (Layer 3 below); the remaining
assertions cover the maximum-obtainable-exposure feature (calculation,
MSA policy, figure metadata/footnotes, plotting, and a live Shiny
reactive-graph test) added afterward.

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

**Complete, 2026-08-20.** A separate review process — not the effort that
wrote the engine, the specification, or this report — independently
re-derived results for a representative set of scenarios and edge cases
from the specification and raw reference/workbook data, computing every
value from scratch before ever reading the engine's own source code. Full
detail: `docs/independent_engine_audit.md`; row-level detail:
`audit/independent_engine_findings.csv`.

**Method.** Four independent lines of evidence: (1) a from-scratch Python
re-implementation of the full calculation chain, written only from the
specification's equations, never importing or calling any R engine code;
(2) direct static reading of the primary audited source workbook (OOXML
zip, no Excel, no COM, no macros — SHA-256 verified unchanged before and
after); (3) the live R engine, run for comparison only after (1) and (2)
were computed; (4) the prior independently-reconstructed fixture set
(`inst/fixtures/`) as a third opinion.

**Result: 100 items checked. 89 PASS. Zero `CONFIRMED_ERROR`. Zero
`POTENTIAL_ERROR`.** The remainder: 6 `DOCUMENTATION_GAP`, 4
`ROBUSTNESS_ISSUE`, 1 `REQUIRES_HUMAN_REVIEW`.

| Status | Count | Disposition |
|---|---:|---|
| `PASS` | 89 | No action |
| `DOCUMENTATION_GAP` | 6 | **Corrected** — specification updated 2026-08-20, see its change-control log (v1.1.0) |
| `ROBUSTNESS_ISSUE` | 4 | **Corrected in code** and covered by new regression tests, see below |
| `REQUIRES_HUMAN_REVIEW` | 1 | Referred to the assessment team — a defect in the *source workbook itself* (see below), not something this project can resolve |
| `CONFIRMED_ERROR` | 0 | — |
| `POTENTIAL_ERROR` | 0 | — |

### What the audit confirmed is correct

Every unit conversion in the chain (kg↔g↔mg, ha↔m², %↔fraction, TKW↔seed
mass, mass↔count seeding rate, both rate-unit directions) is exact to
machine precision, with no factor-of-1000 error and no ha/m² slip found.
Dose per seed, field rate, surface seed density, food ingestion rate, seeds
required per day, EDE, RQ and duration above an effects metric all
reproduce the audited workbook's own cached values to 13-16 significant
figures. `RQ = dose / effects metric` is bit-for-bit exact (`identical()`
`TRUE`) across all 125,280 time-course rows checked. The two dissipation
half-lives are genuinely independent (verified in the workbook's named
ranges, the reference data, the code, and by override experiment). The
screening clothianidin conversion has zero call sites in production code —
stronger than "isolated," it is simply unreachable. MSA feasibility
provably never caps regulatory dose or RQ (verified by code reading,
exhaustive search, and an override experiment giving bit-identical doses).
No dry-to-fresh mass conversion is applied, matching the workbook, which
holds moisture data and deliberately does not use it either.

### The one substantive finding: `seeding_rate_bound` labelling (AUD-027)

Not a numerical error. Specification §4.2 (pre-correction) described a
one-dimensional bound with an asymmetric TKW pairing; the engine actually
implements — and the audited workbook's `Seeding Assumptions!J:M` block
also implements — a full 2×2 grid where the seed count depends on both the
seeding-rate bound and the seed-mass bound. **The code is correct; the
specification was wrong**, and has been corrected (see the specification's
own change-control log). Consequence: a `scenario_inputs` row labelled
`seeding_rate_bound = "low"` can carry a seed count up to 2.5× the figure
the published Word tables call the "lower bound" (winter wheat: 1,500,000
vs. 600,000). **No dose, EDE, RQ, feasible dietary fraction, or required
search area is affected** — the audit proved this algebraically and
confirmed it numerically across all 125,280 rows. Only raw seed-count
columns (`seeds_per_ha`, `seeds_per_m2`, `initial_surface_seeds_per_m2`,
`area_per_surface_seed_m2`, `available_seeds_within_msa`,
`seeds_required_full_diet`) are affected, and the grid's min/max coincide
exactly with the historically reported bounds. **Any regulatory table drawn
from `scenario_inputs` must display `seed_mass_bound` alongside
`seeding_rate_bound`.**

### Four robustness defects — corrected

All four were fixed in code on 2026-08-20 and are covered by new regression
tests (448 total assertions now pass, up from 424; see Layer 1 above).

1. **`diet_fraction = 0` crashed `build_scenario_summary()`** (AUD-088),
   even though specification invariant 6 names it a valid input.
   `days_diet_fraction_feasible()` now treats a zero target as trivially,
   permanently feasible (`Inf`) instead of rejecting it.
   `R/calculations/05_feasibility.R`; test:
   `test-05-boundaries-and-errors.R`, *"a zero target dietary fraction is
   trivially feasible forever (AUD-088)"*.
2. **`clear_override(params, parameter)` always errored** with its
   documented default `scope = NULL` (AUD-095) — a zero-length logical from
   comparing a character vector against `NULL` collapsed the whole
   selection vector. Now builds the scope-match vector explicitly at full
   length regardless of `scope`. `R/inputs/11_parameter_set.R`; test:
   `test-05-boundaries-and-errors.R`, *"clear_override(params, parameter)
   works with its documented default scope (AUD-095)"*.
3. **A `seeds_per_ha` override left `seeding_rate_kg_per_ha` (and hence
   `field_rate_g_ai_per_ha`) stale** (AUD-094), silently violating the
   row's own `seeds_per_ha × TKW / 1e6 = seeding_rate_kg_per_ha` identity.
   The mass-basis default now recomputes from the effective seed count
   whenever the seed count is overridden and the mass rate is not — the
   same pattern already used for body-weight → food-intake propagation.
   `R/summaries/20_scenario_inputs.R`; test:
   `test-07-scenario-builders.R`, *"a seeds_per_ha override propagates into
   the mass seeding rate (AUD-094)"*.
4. **A global-scope dissipation-half-life override silently rewrites every
   crop** (AUD-093). This is the documented fallback behaviour of
   `effective_value()`, not a bug, but it was undocumented as a hazard.
   Documented in `docs/user_guide.md`'s Editable-assumptions section; no
   code change (fixing it would mean *removing* a working, arguably
   correct fallback design — left for a deliberate future decision if the
   interface should scope these two fields per-crop instead).

### One item referred to the assessment team, not resolved here (AUD-031)

For crops whose seeding rate is supplied on a mass basis, the **audited
source workbook itself** reports two different "low bound" surface seed
densities on the same crop sheet (buckwheat: 53.62 seeds/m² in `7!D7`
versus 68.97 seeds/m² implied by `7!J79`/`7!M20`). This model cannot match
both and consistently follows the crop-sheet feasibility convention.
**This is a defect in the source document, not in this model**, and which
convention the assessment intends is a scientific judgement outside this
project's scope.

### One open process gap, not yet closed (AUD-099)

Specification §13 names 28 fixture calculation checks as an acceptance
criterion; no code currently reads that fixture file, so the criterion is
not machine-enforced. The specification wording has been corrected (the
criterion now correctly says "compare against a value recomputed from
exact inputs," not the fixture's own rounded stored figure — several
fixture values cannot meet 1e-6 tolerance against an exact recomputation
purely because they were manually computed from rounded intermediates, and
the engine's exact values are the correct ones in those cases). **Actually
implementing the automated fixture-driven comparison remains an open,
recommended follow-up** — see `PROJECT_STATE.md`.

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

## Feature addition: maximum obtainable exposure (2026-08-20, post-audit)

After the independent engine audit above completed and its findings were
corrected, one feature was added: a "maximum obtainable exposure" analysis
distinguishing the conventional conditional RQ (assumed dietary fraction,
uncapped) from a new availability-constrained maximum-obtainable RQ (capped
at the lesser of the receptor's food requirement and treated seed available
within the source assessment's own MSA policy — see specification §10.4
and model walkthrough §10). This reuses the already-audited engine
functions (`daily_ai_intake_dose()`, `risk_quotient()`,
`available_seed_within_msa()`) and adds two small new primitives
(`resolve_msa_term_for_metric()`, `max_obtainable_seeds_per_day()`), new
canonical columns on `daily_timecourse`, a summary/annotation layer, figure
metadata/footnote generation for self-contained exported figures, plotting
functions, and a new Shiny tab.

This feature has its own test coverage (part of the 556 assertions above,
including a live Shiny reactive-graph test) but **has not yet completed its
own independent adversarial review** — that review was launched
immediately after implementation and, per the same standard applied to the
core engine, was performed by a process that did not write the feature.
Its result will be appended here once complete; until then, treat this
specific feature's correctness as implemented-and-self-tested, not yet
independently confirmed, distinct from the core engine's audited status
above.

## Overall verdict

**The quantitative core of this engine is sound.** An independent process
that did not write the code, the specification, or the tests re-derived
100 representative calculations from scratch — agronomic conversions,
exposure, dose, risk quotient, time-dependent dissipation, and MSA
feasibility — and found **zero confirmed or potential numerical errors**.
For the outputs that matter most for a regulatory judgement
(`dose_mg_kg_bw_day`, `rq`, `days_above_loc`, `threshold_diet_fraction_pct`),
the audit found no error of any kind, checked against the audited source
workbook's own cached values to 13-16 significant figures where a workbook
cell existed to check against.

What was found and has now been corrected: one specification section that
described different (and less internally coherent) behaviour than the code
actually implements — the code was right, the document was wrong, and the
document is now fixed; and four robustness defects (crashes or stale
values on specific override/edge-case paths, none of them silent numerical
errors), three of which are now fixed in code with new regression tests,
the fourth documented as an intentional-but-previously-unwarned design
choice.

**What remains before this can be relied on for a regulatory submission:**
Layer 4 (a human reviewer's own manual acceptance testing, using
`docs/manual_acceptance_test.md`) has not yet been performed. The
fixture-driven automated acceptance check named in specification §13 is
not yet implemented (AUD-099). One source-workbook internal inconsistency
(AUD-031) needs a scientific judgement call from the assessment team, not
an engineering fix. Five of the six crop workbooks (`small_cereals_msa`,
`canola`, `cucurbits`, `legumes_deep`, `legumes_shallow`) have not received
the same 1,115-check independent numeric audit that `small_cereals` did in
the source review project — the calculation *engine* code is identical and
now independently audited across all of them structurally, but the
*underlying workbook data* for those five carries less individual scrutiny
than Small Cereals. See "Crop coverage" above.
