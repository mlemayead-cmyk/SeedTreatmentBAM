# Raw/key-day/grouped result architecture and aggregation specification

**Derived from:** ADR-009 (raw + key-day persistence), ADR-010 (reporting
groups), ADR-011 (grouped-result content). See those entries for
rationale and rejected alternatives (the rejected "representative slice"
concept in particular).

---

## 1. Layer summary

```text
Run
 +-- scenario_inputs        (complete, every scenario)
 +-- scenario_summary       (complete, every scenario x receptor x metric x diet fraction)
 +-- key_day_results        (complete scenario coverage, milestone days only)
 +-- [full daily time course]   <- generated on demand, never persisted by default
 +-- grouped_results        (compact, one row per group x dimension combination)
 +-- grouped_result_bounds  (companion, one row per scenario at a bound)
```

`scenario_inputs` and `scenario_summary` are unchanged in shape from the
current engine's output (`R/summaries/20_scenario_inputs.R`,
`R/summaries/23_scenario_summary.R`) — this specification does not modify
them, only adds `key_day_results` and the grouped layer.

## 2. `key_day_results` schema

One row per (scenario, receptor, metric, diet fraction, milestone day) —
the same grain as `daily_timecourse` today, but restricted to a small,
named set of days per scenario rather than every day:

| Column | Description |
|---|---|
| `scenario_id` | Foreign key to `scenario_inputs`. |
| `receptor` | Receptor identifier. |
| `metric` | Effects metric identifier. |
| `diet_fraction` | Diet-fraction identifier, where applicable. |
| `day` | The actual day number for this row. |
| `day_label` | `peak`, `1`, `2`, `5`, `10`, `30`, or `custom` — identifies *why* this day is included, independent of its numeric value. |
| `value` | The computed metric value (RQ, dose, or whichever quantity the existing daily-timecourse builder produces) at that day. |

**Standard milestone set**: `peak`, day 1, 2, 5, 10, 30 (ADR-009). This
set may be extended with additional standard days if a clear need
emerges; extension is additive (new `day_label` values), not a schema
change.

**Peak-finding.** `day_label = "peak"`'s `day` value is **computed, not
assumed to be 0** (ADR-009's explicit requirement, correcting the current
`R/summaries/23_scenario_summary.R` behaviour of hard-coding
`peak_rq_day <- 0`). Recommended mechanism: evaluate the relevant
day-dependent function (the same closed-form evaluation
`build_daily_timecourse()` already performs at any given day) over a
sufficiently fine day grid spanning the scenario's relevant time horizon,
and take the argmax. For the current, independently-verified monotonic
model, this is expected to still resolve to day 0 in every case; the
mechanism must not special-case that outcome, so a future model version
with different time-dependent behaviour is handled correctly without
code changes to the peak-finder itself. Exact grid resolution is an
implementation-time performance/precision tradeoff, not fixed here.

**Custom days**: a run may request specific additional days be included
in `key_day_results` at run-creation time (`day_label = "custom"`, with
the actual day value recorded). Per Q003 (open), whether user-requested
custom days *outside* of run creation are retroactively added to a
persisted run's `key_day_results` or always served as a separate
on-demand query is not yet decided — implementers should treat
`key_day_results` as append-only-at-creation until Q003 is resolved, and
implement custom-day requests made *after* run creation as on-demand,
unpersisted queries (the more conservative reading of ADR-009, consistent
with "never silently grow a frozen run's persisted data after the fact").

## 3. On-demand full daily time course

Generated only when explicitly requested, scoped to user-selected
scenarios, receptors, metrics, and reporting groups, over a user-selected
day range (ADR-009). Reuses the existing `build_daily_timecourse()`
machinery unchanged, called with the requested day range and scenario
subset rather than the full cross-product. Never automatically triggered
by viewing a grouped or individual result — always an explicit user
action, gated in the Shiny figure/results screens
(`shiny_information_architecture.md` §5, §7) by a visible scope selector,
specifically to avoid recreating the "on the order of a gigabyte" problem
the current architecture's full daily-timecourse builder already
documents.

## 4. Aggregation query shape (ADR-010)

A grouped result is always the composition of:

```text
crop reporting group (from one selected crop-grouping scheme, ADR-010)
  x application rate
  x planting method
  x receptor
  x effects metric
  x (assumption-set IDs, where a comparison across sets is requested)
```

The **crop-grouping scheme** is the only dimension that ever groups
*crops* together. Every other dimension listed above is either held fixed
(filtered to one value) or itself used as a comparison/series dimension
(ADR-013) — never silently folded into the crop-grouping scheme itself.

## 5. `grouped_results` schema

One compact row per (grouping scheme, group label, selected reporting-
dimension combination):

| Column | Description |
|---|---|
| `group_scheme_id` | The `reporting_sets` scheme used (ADR-010). |
| `group_label` | The group within that scheme. |
| `rate_level`, `planting_method`, `receptor`, `metric`, ... | The held-fixed or filtered dimension values that scope this row (exact column set depends on which dimensions are in play for a given query — see §6 on schema flexibility). |
| `assumption_set_ids` | The assumption-set IDs in effect, where relevant to distinguish comparable groups. |
| `min_value`, `max_value` | The range (ADR-010 — never a mean/median). |
| `min_scenario_id`, `max_scenario_id` | Stable reference to the underlying raw scenario/result ID driving each bound (ADR-011) — **not** crop name alone, since the same crop can appear under many rate/method/receptor/metric/assumption-set combinations. When tied, holds one deterministically-chosen representative (see §7). |
| `n_scenarios` | Count of contributing raw scenarios. |
| `n_crops` | Count of distinct contributing crops. |
| `min_tied`, `max_tied` | Boolean — `TRUE` when more than one scenario shares the extreme value at that bound (ADR-011). |

Additional counts (`n_use_patterns`, `n_assumption_sets`, etc.) are added
**only when a specific reporting/traceability purpose is identified**
(ADR-011's explicit instruction against speculative fields) — none are
included by default in this specification.

**Single-contributor groups**: `min_value = max_value`,
`min_scenario_id = max_scenario_id` (the same scenario), `n_scenarios =
n_crops = 1`, both tie flags `FALSE`. The row shape is unchanged; the
counts make clear this is not a true range (ADR-011).

## 6. Schema flexibility note

The "dimension" columns in `grouped_results` (rate, planting method,
receptor, metric, assumption-set IDs) are not a fixed, exhaustive column
list applied identically to every row — which dimensions are held fixed
vs. varied depends on the specific grouped query that produced a given
set of rows (per ADR-010's composed query shape). Implementers should
treat the dimension columns as the *currently selected* reporting
dimensions for a given grouped-results table/view, not as a universal
schema every `grouped_results.csv` must populate identically.

## 7. `grouped_result_bounds` companion table (ADR-011)

Preserves tie membership without embedding the full raw group:

| Column | Description |
|---|---|
| `group_row_key` | Foreign key back to the owning `grouped_results` row (group scheme, group label, full reporting-dimension combination). |
| `bound_type` | `min` or `max`. |
| `scenario_id` | One contributing scenario at that bound. |

Exactly one row per non-tied bound; one row per tied scenario for a tied
bound. This table is deliberately **not** a full dump of every
contributing scenario in the group — only the scenario(s) actually at a
bound — keeping the raw/grouped separation intact (ADR-011's explicit
rejection of embedding every contributing value).

**Deterministic representative selection** for the primary table's single
`min_scenario_id`/`max_scenario_id` when tied: recommend the
lowest-sorted `scenario_id` among tied scenarios. This must be documented
in the implementation (not left as an unstated arbitrary choice) precisely
because a reviewer could otherwise perceive it as an unexplained pick.

## 8. Drill-down data path

`grouped_result_bounds.scenario_id` (and, more generally,
`min_scenario_id`/`max_scenario_id`) is the mechanism the Shiny Results
and Figures screens use to jump from a grouped envelope/range to the
individual or raw view for the scenario(s) driving a given bound
(`shiny_information_architecture.md` §5, ADR-013).

## 9. Explicit non-goals

- No mean/median or other central-tendency statistic is computed at the
  grouped layer by this specification (ADR-010).
- No dimension other than crop is ever grouped by a "grouping scheme" —
  rate, planting method, receptor, metric, and assumption-set comparisons
  are handled as separate reporting/series dimensions
  (`table_and_figure_architecture.md`), never folded into
  `reporting_sets/`.
