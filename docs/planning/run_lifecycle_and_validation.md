# Save/validation and run lifecycle specification

**Derived from:** ADR-006 (GUI editing/validation), ADR-007 (save
behaviour), ADR-008 (run lifecycle). See those entries for rationale.

---

## 1. Save mechanics

Two coexisting save granularities, never live/immediate save (ADR-007):

- **Per-table save**: validates and writes exactly one input table.
  Failure leaves the previously saved file untouched and reports the
  specific validation failure (per `folder_and_input_schema.md` §4).
- **Whole-evaluation save-all**: validates every currently-dirty table;
  if *any* fails, *none* are written (all-or-nothing).

**Dirty-state tracking**: the GUI layer must track, per table, one of
`clean` / `dirty` / `saved`. This state must be visible in the UI
(`shiny_information_architecture.md` §3) and drives whether the
Save-all action is enabled.

**Implementation shape (recommended, not fixed by any ADR)**: one
validation function per table (columns/types/permitted-values/
referential-integrity/uniqueness/range rules, per
`folder_and_input_schema.md` §4), invoked directly for per-table save and
in a loop over all dirty tables for save-all. Both import paths (Shiny
form edits and Excel/CSV upload) call the same validation function, so
rules cannot drift between entry paths.

## 2. Run creation

A **run** is a frozen calculation over a specific, immutable combination
of inputs (ADR-008's governing conceptual model). Creating a run:

1. **Resolve the current input state** — which named set is selected per
   category (agronomy/receptors/effects/fate), plus the current
   `use_patterns.csv` content, plus whichever reporting scheme(s) are
   selected as default for this evaluation.
2. **Compute a content hash** over the canonicalized, concatenated
   content of everything that would go into `inputs_snapshot/` (ADR-008's
   deduplication recommendation). Canonicalization must be deterministic
   (e.g. stable row/column ordering, consistent numeric formatting)
   so that two logically-identical input states always hash identically
   regardless of incidental factors like file-write order.
3. **Compare against existing runs' stored hashes** (from their
   `run_manifest.csv`):
   - **Match**: surface this to the user by name/ID; offer "use the
     existing run" or "force a new run anyway." Never silently reuse,
     never silently skip, never silently create a duplicate.
   - **No match**: proceed to step 4.
4. **Freeze `inputs_snapshot/`** — write a complete copy of every input
   file actually used (every selected named set's file, plus
   `use_patterns.csv`, plus the selected reporting scheme file(s)).
5. **Compute raw results** — `scenario_inputs`, `scenario_summary`,
   `key_day_results` (unchanged engine, per
   `result_architecture_and_aggregation.md`).
6. **Compute grouped results** — for whatever grouping scheme(s)/
   dimensions are configured as this evaluation's default grouped view
   (`result_architecture_and_aggregation.md`).
7. **Write `run_manifest.csv`** (schema below).

## 3. `run_manifest.csv` schema

One manifest per run, at `outputs/runs/Run_<NNN>/run_manifest.csv` (or an
equivalent single-row/key-value structure — exact serialization is an
implementation choice; the field list below is what matters):

| Field | Description |
|---|---|
| `run_id` | Stable identifier (e.g. `Run_001`). |
| `created_at` | Timestamp. |
| `description` | Optional user-supplied label (e.g. "2026 seeding + generic receptors"). |
| `content_hash` | Deterministic hash used for deduplication (§2 step 2). |
| `seeding_set_id`, `receptor_set_id`, `effects_set_id`, `fate_set_id` | IDs of the named sets used (ADR-004 point 6). |
| `reporting_scheme_ids` | ID(s) of the reporting/grouping scheme(s) used for this run's default `grouped_results/` (ADR-010). |
| `model_version` | `STBAM_MODEL_VERSION` (or equivalent) at run time. |
| `git_commit` | Repository commit hash at run time, where available. |
| `validation_status` | Result of any automated validation/invariant checks run at creation time. |

`model_version`/`git_commit` here are the calculation-engine's version —
kept distinct from the reporting/table-builder and figure-builder version
identifiers introduced in `reproducibility_and_provenance.md`, which
track the *presentation* logic, not the *calculation* logic.

## 4. What "frozen" means in practice

- `inputs_snapshot/` is never modified after a run is created. Later
  edits to a named set or `use_patterns.csv` in the evaluation's live
  `inputs/` do not affect any existing run's snapshot or results.
- `raw_results/` and `grouped_results/` are derived deterministically
  from `inputs_snapshot/` plus the recorded `model_version` — this is
  what makes on-demand regeneration (full daily time course, custom-day
  queries, new grouping-scheme views over an old run) exactly
  reproducible without needing to persist everything up front (ADR-009).
- Deleting a run deletes its entire `Run_<NNN>/` folder; nothing outside
  that folder depends on it (tables/figures reference a run by ID and
  must handle a missing run gracefully — see
  `table_and_figure_architecture.md`).

## 5. Explicit non-goals

- This specification does not define how figures/tables/reports are
  generated from a run — that is `table_and_figure_architecture.md`.
- This specification does not fix the exact canonicalization/hashing
  algorithm (SHA-256 vs. another deterministic hash) — implementation
  detail, tracked in `invariants_and_test_plan.md` as something the
  reproducibility invariant tests must exercise.
