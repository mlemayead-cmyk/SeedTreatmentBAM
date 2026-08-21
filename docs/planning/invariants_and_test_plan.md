# Architectural invariants and test plan

**Derived from:** the full ADR log (ADR-001 through ADR-015) and the
original redesign request's own list of architectural invariants to
test. This document restates those invariants concretely, grounded in
the decisions actually made, and specifies how each is tested. If the
original request's invariant list (not reproduced verbatim here — this
document reconstructs it from the decision record) differs from this
list in wording, reconcile at implementation time; the substance below
is derived directly from Accepted ADRs, not invented independently.

---

## 1. Invariant list

| # | Invariant | Source ADR(s) |
|---|---|---|
| I1 | `inputs/` is always complete, self-contained data — never an override/diff against `data/reference/` or against another evaluation. | ADR-002, ADR-003, ADR-004 |
| I2 | `outputs/` is always fully regenerable from `inputs/` + the recorded `model_version` — safe to delete and rebuild. | ADR-002 |
| I3 | Updating `data/reference/` never retroactively alters an existing evaluation's `inputs/`. | ADR-003 |
| I4 | A run's `inputs_snapshot/` is immutable; later edits to a shared named set never change an existing run's recorded inputs or results. | ADR-008 |
| I5 | A distinct scientific configuration is never silently overwritten or silently skipped by the run-deduplication mechanism — a hash match is always surfaced to the user with an explicit choice. | ADR-008 |
| I6 | Grouped results are always a range (`min`/`max`), never a mean/median or other central-tendency statistic presented without explicit justification. | ADR-010 |
| I7 | A crop-grouping scheme groups crops only — it never folds rate, planting method, receptor, or effects metric into the group definition itself. | ADR-010 |
| I8 | A tie at a grouped-result bound is always recorded (`grouped_result_bounds`) and exposed via the tie flags — never silently resolved to "the first" match with no trace. | ADR-011 |
| I9 | `key_day_results`' peak day is always the result of an actual search/evaluation for that specific scenario/receptor/metric/diet-fraction combination — never a hard-coded constant. | ADR-009 |
| I10 | Re-running an unchanged evaluation (same inputs, same `model_version`) reproduces identical raw and grouped canonical results. | ADR-008, ADR-009 |
| I11 | Migration reproduces `scenario_inputs`/`scenario_summary` identical to the pre-migration engine output, for the current project's data. | ADR-015 |
| I12 | A table or figure **definition**'s displayed values are always recomputed live from its source run — never a stored, independently-drifting data copy. | ADR-012, ADR-013 |
| I13 | A persisted table/figure **export** is a frozen snapshot that never changes after creation, even if its source run or definition later changes. | ADR-012, ADR-013 |
| I14 | No table or figure is ever written to disk as a side effect of ordinary Shiny viewing — only an explicit Export/Save-snapshot/Add-to-report action persists a file. | ADR-012, ADR-013 |
| I15 | A failed validation (GUI edit or Excel/CSV import) never replaces a previously saved, valid input file. | ADR-006 |
| I16 | The validated calculation engine's semantics are never changed by this redesign's implementation without an explicit, separately-approved **SCIENTIFIC MODEL CHANGE** decision. | Document header, all ADRs |
| I17 | Every persisted artifact (run, table/figure definition, table/figure export) carries provenance sufficient to answer "what produced this and with what versions" (`reproducibility_and_provenance.md`). | ADR-004, ADR-008, ADR-009, ADR-012, ADR-013, ADR-015 |

## 2. Test strategy per invariant

| # | Test approach |
|---|---|
| I1 | Static check: no evaluation input file contains an "overrides"/diff-style structure; schema validation confirms every input table is a complete table per `folder_and_input_schema.md`. |
| I2 | Delete `outputs/` for a test evaluation, regenerate from `inputs/`, compare against a retained copy — must match exactly. |
| I3 | Edit a `data/reference/` file after an evaluation exists; confirm the evaluation's `inputs/` is unchanged. |
| I4 | Create a run, then edit the named set it used; confirm the run's `inputs_snapshot/` and results are byte-identical to before the edit. |
| I5 | Attempt to create a run with unchanged inputs; assert the existing-run match is surfaced and no duplicate run is silently created; separately assert "force new run" does create one, explicitly. |
| I6 | Schema/contract test: `grouped_results` never contains a mean/median column; only `min_value`/`max_value`. |
| I7 | Attempt to construct a `reporting_sets` scheme keyed on a non-crop dimension (e.g. planting method) and assert it is rejected by the scheme's own schema (`crop`, `group_label` only — `folder_and_input_schema.md` §2.2). |
| I8 | Construct a grouped result with a deliberate tie; assert `grouped_result_bounds` contains all tied scenarios and the tie flag is set. |
| I9 | Unit test the peak-finder against a synthetic non-monotonic day-dependent function (not the current model) and confirm it finds the true argmax, not day 0 — proves the mechanism is general, not special-cased. |
| I10 | Run the same evaluation twice with no input changes; assert `content_hash` matches and (on "force new run") raw/grouped results are identical. |
| I11 | The migration plan's own verification step (`migration_plan.md` §4) — automated, re-run at implementation time and in CI if feasible. |
| I12 | Change a run's grouped results is not possible directly, but confirm that re-opening a saved table/figure definition after its source run's underlying data changes (should not normally happen for a frozen run, but test via a second run with different inputs pointed at the same definition's configuration) always reflects the *current* run state, never a stale cached value. |
| I13 | Export a table/figure, then (hypothetically) alter the definition or point it at a different run; confirm the previously exported file is unchanged on disk. |
| I14 | Open and browse tables/figures in a test session; assert no new files appear under `outputs/tables/exports/` or `outputs/figures/exports/` without an explicit export action. |
| I15 | Attempt an invalid Excel import (bad type, out-of-range value, broken referential integrity) and a bad GUI edit; assert the previously saved file is byte-identical afterward in both cases. |
| I16 | Code-review/diff check as part of any implementation PR: no change touches `R/calculations/*.R` semantics unless explicitly flagged and separately approved. Existing independent-review methodology (`docs/independent_engine_audit.md`'s approach) is reused for any such flagged change. |
| I17 | For a sample run, table export, and figure export, confirm every required provenance field from `reproducibility_and_provenance.md` §2 is present and non-empty. |

## 3. Regression protection for the existing engine

Because I16 is the highest-stakes invariant, implementation work should:
- Run the existing test suite (`tests/testthat/`) unchanged and passing
  before and after every implementation phase.
- Treat any test failure touching `R/calculations/*.R` as a stop-and-flag
  event, not something to "fix" by adjusting the calculation code without
  separate human approval.
- Reuse the existing independent-review pattern (a separate reviewing
  agent/person, not self-certifying). **Risk-based policy, adopted this
  session (ADR-019, `assessment_workspace_architecture.md`)**: independent
  adversarial review is mandatory for any ticket in one of these
  categories — (1) peak/key-day calculation logic, (2) the evaluation-
  inputs → engine-parameter-set adapter, (3) migration equivalence, (4)
  run freezing/persistence/reproducibility, (5) aggregation/range logic
  and min/max bound traceability, (6) grouped/time-dependent envelope
  calculations, (7) figure traceability across multiple runs/assumption
  sets. Routine GUI/layout/plumbing tickets do not individually require
  it, unless implementation evidence raises a specific concern. See
  `implementation_phases_proposal.md` §"Independent-review policy
  application" for which ticket in each phase this applies to.

## 4. Where this plan is exercised

Each implementation phase in `implementation_phases_proposal.md` lists
which of I1–I17 it is responsible for demonstrating before that phase is
considered complete.
