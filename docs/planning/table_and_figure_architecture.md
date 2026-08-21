# Table and figure architecture specification

**Derived from:** ADR-012 (tables) and ADR-013 (figures). See those
entries for rationale, including the user's explicit definition/live-
render/export-snapshot pattern and the level-of-detail vs. series/
comparison-dimension distinction for figures.

---

## 1. Shared pattern

Both tables and figures follow the same three-stage pattern:

```text
Preserved run results
        |
        v
Saved definition (small, reusable, editable — never a data/image copy)
        |
        v
Live Shiny view (recomputed/re-rendered from the run every time)
        |
        +----> explicit Export / Save snapshot / Add to report
                    |
                    v
             frozen file (CSV/XLSX/Word or PNG/SVG)
```

Ordinary viewing in Shiny **never** writes a persisted file. A file is
written only by a deliberate user action.

## 2. Table definitions

Stored under `outputs/tables/definitions/` (per
`folder_and_input_schema.md` §1). Minimum fields:

| Field | Description |
|---|---|
| `definition_id` | Stable identifier. |
| `title`, `description` | Human-readable labels. |
| `run_id` | Source run. |
| `group_scheme_id` | Reporting/grouping scheme in use, if any. |
| `dimensions_retained`, `dimensions_aggregated` | Which reporting dimensions (rate, planting method, receptor, metric, assumption-set IDs) are kept distinct in this table's rows vs. rolled into the grouped range (per `result_architecture_and_aggregation.md` §4). |
| `filters` | Any fixed-value filters applied. |
| `columns` | Which columns to display, in what order. |
| `formatting` | Display options (units, decimal precision, labels). |

Opening a definition in Shiny always recomputes its displayed values from
the current state of `run_id`'s `grouped_results`/`raw_results` — there is
never a second stored copy of the numbers.

## 3. Table export

Triggered only by an explicit Export / Save-snapshot / Add-to-report
action. Produces a frozen file under `outputs/tables/exports/` (CSV,
XLSX, or a Word-embeddable table), which does not update if the source
run or definition later changes.

**Required export metadata** (embedded in the file or a sidecar,
consistent with `reproducibility_and_provenance.md`): evaluation identity,
`run_id`, the table definition/configuration that produced it (or a
reference to the saved `definition_id`), generation timestamp,
`model_version`, and the reporting/table-builder version in effect at
export time.

## 4. Figure definitions

Stored under `outputs/figures/definitions/`. Minimum fields:

| Field | Description |
|---|---|
| `definition_id` | Stable identifier. |
| `title`, `description` | Human-readable labels. |
| `run_id` | Source run. |
| `metric` | Effects metric / exposure quantity plotted. |
| `detail_level` | `grouped`, `individual`, or `raw` (ADR-013). |
| `series` | One or more series specifications (§5) — independent of `detail_level`. |
| `group_scheme_id` | Reporting/grouping scheme, when `detail_level = grouped`. |
| `filters` | Fixed-value filters. |
| `time_selection` | Key days / custom days / a selected range (per `result_architecture_and_aggregation.md` §2-3). |
| `display_settings` | Axis, colour, legend, and similar presentation options. |

### 4.1 Level of detail vs. series (ADR-013)

These are independent axes, not one combined setting:

- **`detail_level`** determines *how* each series is rendered:
  - `grouped` -> a min–max envelope, using `grouped_results`/
    `grouped_result_bounds`.
  - `individual` -> one trajectory per selected crop/entity.
  - `raw` -> one trace per selected raw scenario.
- **`series`** determines *what* is compared — one or more of: crop or
  reporting group, rate, receptor, receptor size, seeding-assumption set,
  receptor set, run, exposure characterization (conditional vs.
  maximum-obtainable RQ), etc. A figure may show multiple series at the
  same `detail_level` (e.g. two grouped envelopes comparing assumption
  sets, or four individual crop trajectories).

### 4.2 Grouped-envelope requirements

- Rendered as a min–max band across the time/x-axis.
- **Mandatory accompanying footnote/metadata** stating that the scenario
  driving the upper or lower bound may change across the axis — the
  envelope must never be presented as if either edge is one continuous
  crop/scenario's trajectory (ADR-013's explicit scientific-communication
  requirement). Extends the existing `format_figure_footnotes()` pattern.
- Bound identity (`min_scenario_id`/`max_scenario_id`,
  `grouped_result_bounds` tie membership) must be reachable from the
  figure — e.g. by clicking/hovering an envelope edge — for drill-down
  into the individual/raw view.

### 4.3 Individual and raw view selection

Neither `individual` nor `raw` auto-plots every available entity. Series
selection is always explicit. Recommended (non-blocking) UX controls,
per ADR-013:

- **Individual**: multi-select of crops/entities; shortcuts for "crops
  currently driving the group's min/max envelope" (sourced directly from
  `grouped_result_bounds`) and "selected focal crops"; an "all" option
  gated by a soft warning once the count risks unreadability.
- **Raw**: selection of specific scenario IDs, primarily reached by
  drilling down from a grouped or individual view rather than browsing
  the full raw table cold.
- A general soft "this selection may be hard to read" warning (not a hard
  block) when the chosen series count/combination is likely to produce
  clutter — exact heuristics are implementation-phase design.

## 5. Series specification schema

Each entry in a figure definition's `series` list:

| Field | Description |
|---|---|
| `series_id` | Stable identifier within the definition. |
| `label` | Display label. |
| `entity_type` | `crop`, `reporting_group`, `rate`, `receptor`, `assumption_set`, `run`, `exposure_characterization`, etc. |
| `entity_value` | The specific value(s) selected for this series. |
| `run_id` | Usually the definition's own `run_id`, but a series may reference a *different* run when the comparison dimension is "different runs" (ADR-013 explicitly lists this as a valid comparison). |

## 6. Figure export

Same pattern as table export (§3): explicit action only, captures exactly
the currently configured view (`detail_level`, `series`, `filters`,
`group_scheme_id`, `metric`, `time_selection`, `display_settings`) as a
frozen PNG/SVG/etc. under `outputs/figures/exports/`. Exporting one
figure never automatically generates every combination or all three
detail levels — this is the specific mechanism by which this
specification avoids recreating the current architecture's ~581-file
static batch output.

**Required export metadata**: same fields as table export (§3), plus a
figure-builder version identifier (`reproducibility_and_provenance.md`).

## 7. Explicit non-goals

- No automatic "generate all figures" batch mode in this specification.
- No figure or table ever stores a duplicate copy of numeric results
  outside of an explicit export snapshot.
- Rendering-library/mechanism choice (e.g. which R plotting approach
  produces the envelope band) is implementation detail, not fixed here.
