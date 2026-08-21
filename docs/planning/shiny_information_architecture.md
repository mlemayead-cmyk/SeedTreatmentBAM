# Shiny information architecture specification

**Derived from:** ADR-006, ADR-007, ADR-008, ADR-012, ADR-013, ADR-014.
See those entries for rationale.

---

## 1. Top-level navigation

```text
[App launch]
     |
     v
Evaluation picker / landing screen  (ADR-014)
  - list of evaluations (scan evaluations/*/)
  - Create / Open / Clone / Rename / Delete
     |
     |  (Open or Create)
     v
Evaluation workspace  (one evaluation active at a time)
  - Inputs
  - Runs
  - Results (grouped / individual / raw)
  - Tables
  - Figures
     |
     |  (explicit "Back to evaluations")
     v
Evaluation picker / landing screen
```

Only one evaluation is open in the workspace at a time (ADR-014's chosen
option B). The picker screen owns whole-evaluation lifecycle actions;
the workspace screens own everything scoped to the currently open
evaluation.

## 2. Evaluation picker screen

- Table/grid of evaluations: name, last-modified, last-run date (if any),
  brief description.
- **Create**: prompts for a name, creates the folder structure per
  `folder_and_input_schema.md`, copying `data/reference/` wholesale
  (ADR-003) as the starting named sets.
- **Open**: enters the workspace for the selected evaluation.
- **Clone**: copies an evaluation's `inputs/` (default: inputs only, not
  run history — ADR-014 open follow-up) under a new name.
- **Rename** / **Delete**: operate on the folder as the single movable/
  copyable/deletable unit (ADR-002).

## 3. Evaluation workspace — Inputs screens

One screen area per input category from `folder_and_input_schema.md`:

- **Use patterns** — grid view (`DT`) of `use_patterns.csv`, showing the
  normalized rows but allowing a grouped multi-select entry mode for
  planting methods that explodes to normalized rows on save (ADR-005).
- **Assumption sets** (agronomy / receptors / effects / fate / reporting)
  — per category: a set selector (which named set is currently selected
  for this evaluation's default context) plus set management (view,
  create new named set, edit an existing set's rows, view its
  manifest metadata).

Each editable table provides, per ADR-006:
- A `DT` grid for bulk viewing/review.
- A validated add/edit form or modal for structured single-record
  changes.
- "Download as Excel" (via `writexl`) for external bulk editing.
- "Upload Excel or CSV" (via `readxl`/`readr`) with schema validation
  before any saved file is replaced (`folder_and_input_schema.md` §4).

Save controls, per ADR-007:
- Each table has its own **Save** action (per-table, validated at save
  time).
- A workspace-wide **Save evaluation** action commits every currently
  dirty table together, all-or-nothing.
- No live/immediate save path — every write goes through validation.
- UI must distinguish, per table: unsaved draft / saved / (informational)
  saved-but-newer-than-the-most-recent-run.

## 4. Evaluation workspace — Runs screen

- List of preserved runs (`outputs/runs/Run_*/run_manifest.csv` — see
  `run_lifecycle_and_validation.md`), each showing its ID, date,
  optional description, and the assumption-set IDs used.
- **Run** action: computes a content hash over the would-be
  `inputs_snapshot/` (per ADR-008's deduplication recommendation) and
  compares against existing runs.
  - **Match found**: tell the user explicitly which existing run matches;
    offer "use existing run" or "force a new run anyway" — never silent.
  - **No match**: proceed, creating a new `Run_<NNN>` with a frozen
    `inputs_snapshot/`, `raw_results/` (`scenario_inputs`,
    `scenario_summary`, `key_day_results` — ADR-009), and
    `grouped_results/` computed for whatever grouping scheme(s) are
    selected as default (ADR-010/011). Optional description field
    prompted at creation time.
- Selecting a run makes it the "active run" for the Results/Tables/
  Figures screens below — the UI must show which run is currently active
  everywhere results are displayed (ADR-008 consequence).

## 5. Evaluation workspace — Results screen

Browses a chosen run's raw and grouped results directly (not yet a
table/figure definition — this is ad hoc inspection):
- **Grouped view**: pick a reporting/grouping scheme (ADR-010), pick
  reporting dimensions (rate, planting method, receptor, metric,
  assumption-set IDs); view resulting ranges with bound identity and tie
  indicators (`+N tied`) from `grouped_result_bounds` (ADR-011).
- **Individual view**: select specific crops/entities to inspect directly
  (no scheme applied).
- **Raw view**: select specific scenario IDs to inspect at full
  resolution, including on-demand full daily time-course generation
  (bounded scope: selected scenarios/receptors/metrics + day range —
  ADR-009).
- Clicking a grouped bound's identified driver (`min_scenario_id`/
  `max_scenario_id`) is the drill-down entry point into the individual/
  raw views (ADR-011, ADR-013).

## 6. Evaluation workspace — Tables screen

- List of saved table **definitions** (ADR-012), each showing its title,
  source run, and configuration summary.
- **New table definition**: configure source run, grouping scheme,
  dimensions retained vs. aggregated, filters, receptor/metric selection,
  columns, ordering/formatting, title/description.
- Opening a definition always recomputes its values live from the current
  state of its source run's grouped/raw results (never a stored data
  copy).
- **Export**: produces a frozen CSV/XLSX/Word snapshot of the currently
  configured view, with full provenance (ADR-012 §"Provenance
  requirements") written alongside or embedded in the export.

## 7. Evaluation workspace — Figures screen

- List of saved figure **definitions** (ADR-013).
- **New figure definition**: configure source run, metric, **level of
  detail** (grouped / individual / raw) and, independently, **series
  selection** (what is compared — crops/groups, rates, receptors,
  assumption sets, runs, exposure characterization), filters, time
  selection (key days / custom days / range, per ADR-009), display
  settings.
- Live figure view in Shiny supports switching detail level and series
  selection without leaving the figure (ADR-013's drill-down hierarchy).
- Series-selection controls (proposed, non-blocking per ADR-013):
  multi-select with shortcuts ("crops driving the current envelope
  bounds," "focal crops"), and a soft readability warning (not a hard
  block) when a selection is likely to produce clutter.
- **Export**: captures exactly the currently configured view (detail
  level, series, filters, scheme, metric, time selection, display
  settings) as a frozen PNG/SVG/etc. snapshot, with the same provenance
  requirements as table export (ADR-013).

## 8. Cross-cutting UI requirements

- Every screen that displays results must show which run they are
  sourced from.
- Every export action (table or figure) must be a distinct, explicit
  control — never a side effect of viewing.
- Validation errors on import/edit must be surfaced inline, referencing
  the specific row/column/rule that failed (`folder_and_input_schema.md`
  §4), and must never silently discard the previously saved valid file.

## 9. Explicit non-goals

- No multi-evaluation-at-once view in this specification (ADR-014); a
  future cross-evaluation comparison feature, if ever needed, is a
  separate addition, not part of this IA.
- No automatic bulk figure/table generation screen ("generate everything")
  — this specification deliberately does not recreate the current static
  batch-figure mechanism.
