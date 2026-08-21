# Assessment/evaluation workspace architecture — specification

**Status:** Draft specification, derived from `docs/planning/assessment_workspace_architecture.md`
(ADR-001 through ADR-015, all Accepted). This document is the readable,
implementer-facing synthesis of those decisions; the ADR log remains the
authoritative record of *why* each choice was made and what alternatives
were considered. Where this document and the ADR log ever disagree, the
ADR log is correct and this document has drifted — fix this document, do
not silently trust it.

**Companion specification documents** (each covers one area in more
depth than this overview):
- `folder_and_input_schema.md` — evaluation folder layout, input file
  schemas, assumption-set architecture.
- `migration_plan.md` — converting the current project into the first
  evaluation.
- `shiny_information_architecture.md` — GUI navigation and screens.
- `run_lifecycle_and_validation.md` — save/validation mechanics and the
  run lifecycle.
- `result_architecture_and_aggregation.md` — raw/key-day/grouped result
  layering and the aggregation/reporting-group specification.
- `table_and_figure_architecture.md` — table and figure definitions,
  rendering, and export.
- `reproducibility_and_provenance.md` — version/provenance requirements
  across every layer.
- `invariants_and_test_plan.md` — architectural invariants and how they
  are tested.
- `implementation_dependencies_and_risks.md` — what depends on what, and
  what could go wrong.
- `implementation_phases_proposal.md` — proposed dependency-ordered
  implementation phases (approved with amendments — Decision 16 / Q004,
  resolved; see ADR-016 through ADR-020).

**Scope boundary, restated from the ADR log's header:** this redesign
concerns persistence, data architecture, GUI, workflow, reporting,
aggregation, and output management. It does **not** authorize changes to
validated calculation semantics. Any implementation work that would
require changing calculation semantics must be flagged as
**SCIENTIFIC MODEL CHANGE — HUMAN APPROVAL REQUIRED** and stopped for
explicit review before proceeding, exactly as the ADR log's preamble
requires.

---

## 1. What is changing, and why

The current architecture (`R/inputs/11_parameter_set.R`) is
baseline-plus-override: an immutable `stbam_baseline` read from
`data/reference/*.csv`, plus a per-session `stbam_parameter_set` whose
`overrides` tibble records only what changed from that baseline. This is
documented in the code's own words: `export_scenario_config()`'s
docstring states "Exports only the override layer. The baseline is
reproducible from the source workbooks and is not duplicated into
scenario files."

This works for a single, semi-permanent assessment with occasional
what-if exploration, but does not match the desired product direction:
complete, self-contained, human-readable assessment workspaces that do
not depend on session state or on the concept of an "override" to be
understood. It also does not have any concept of a preserved calculation
*run*, any structured way to group crops for reporting, or any figure/
table architecture beyond a large batch of statically generated images
(`scripts/generate_priority_exposure_figures.R` — 288 logical figures x 2
formats = 581 files, ~200MB).

This redesign replaces that model with **evaluations**: complete,
self-contained folders that the Shiny GUI creates, opens, edits, runs,
and reloads, each holding editable inputs, preserved calculation runs,
and on-demand presentation artifacts generated from a chosen run.

## 2. Governing conceptual model

Stated by the user during the decision process (ADR-008), and adopted as
the model that every other decision in this redesign is checked against:

> Evaluation = the ongoing working assessment.
> Input sets = editable scientific information.
> Run = a frozen calculation using a particular combination of inputs.
> Figures/tables/reports = presentation products generated from a chosen
> run.

Two further governing principles run through every decision:

- **Definition vs. data, everywhere presentation is involved.** Tables
  (ADR-012) and figures (ADR-013) both separate a small, reusable,
  editable *definition* (what to show, from which run) from the *live,
  recomputed view* Shiny renders from that definition, from a *frozen
  export* that exists only after an explicit user action. No layer
  silently duplicates numerical results that could drift from their
  source run.
- **Deliberate, never arbitrary, sampling.** ADR-009 replaced the
  now-rejected "representative slice" (an arbitrary subset of scenarios
  at full daily resolution) with the opposite approach: every scenario,
  at deliberately chosen days. The same discipline — explicit, named,
  reviewable choices rather than convenient sampling — recurs in ADR-010
  (grouping schemes are crop-only, not an arbitrary mix of dimensions)
  and ADR-011 (ties are recorded, never silently resolved to "the
  first").

## 3. Top-level structure

```text
seed_treatment_bam_model/
  data/reference/          <- unchanged central default template (ADR-003)
  evaluations/              <- new: every evaluation lives here (ADR-002/003)
    Evaluation_Name/
      inputs/                <- complete, authoritative, hand-editable (ADR-004/005/006)
      outputs/
        runs/                 <- frozen calculations (ADR-008/009)
        tables/                <- table definitions + exported snapshots (ADR-012)
        figures/               <- figure definitions + exported snapshots (ADR-013)
  R/                        <- unchanged calculation engine, extended with
                                new evaluation/run/aggregation/reporting
                                modules per the companion specifications
  docs/planning/            <- this decision log and specification set
```

One evaluation = one complete active-ingredient risk assessment (ADR-001),
e.g. the migrated `thiamethoxam` project (ADR-015) will be the first.

## 4. How the pieces fit together (data flow)

```text
data/reference/ (central defaults, ADR-003)
       |  (copied wholesale at evaluation creation)
       v
Evaluation/inputs/
  assumptions/{agronomy,receptors,effects,fate,reporting}/*_sets/  (ADR-004)
  uses/use_patterns.csv                                            (ADR-005)
       |  (GUI edit: grid + form, CSV authoritative, Excel round-trip — ADR-006)
       |  (save: per-table or whole-evaluation — ADR-007)
       v
  [Run] — frozen calculation                                       (ADR-008)
       |
       +--> inputs_snapshot/   (immutable copy of every input file used)
       +--> scenario_inputs, scenario_summary (complete, every run)  (ADR-009)
       +--> key_day_results (compact, every scenario, milestone days)(ADR-009)
       +--> grouped_results, grouped_result_bounds                  (ADR-010/011)
       |
       v
  [full daily time course] — generated on demand only, never          (ADR-009)
  auto-persisted, scoped to user-selected scenarios/receptors/
  metrics/groups/day-range
       |
       v
  Table definitions / Figure definitions  --(live render)-->  Shiny view (ADR-012/013)
       |                                                         |
       +----------------------- explicit Export -----------------+
                                     |
                                     v
                     frozen CSV/XLSX/Word/PNG/SVG snapshot
```

## 5. Cross-cutting requirements that apply to every layer

These are restated here because they are easy to lose sight of when
reading any single companion specification in isolation:

1. **Complete files, not overrides, everywhere in `inputs/`.** An
   evaluation's `inputs/` is never a diff against `data/reference/`; it
   is a full, disconnected copy at creation time, subsequently edited in
   place (ADR-003, ADR-004).
2. **A run's reproducibility must survive later edits to shared named
   sets.** `inputs_snapshot/` holds the actual input values used, not
   just set IDs (ADR-008).
3. **Aggregation is always a range with traceable drivers, never a mean/
   median presented without justification**, and never silently mixes a
   use/scenario dimension (rate, planting method, receptor, metric) into
   a crop-grouping scheme (ADR-010, ADR-011).
4. **Presentation artifacts (tables, figures, reports) are generated on
   demand from a chosen run — never automatically bundled into every run
   — and a persisted file exists only after an explicit user action**
   (ADR-008, ADR-012, ADR-013).
5. **A distinct scientific configuration is never silently overwritten or
   silently skipped** — deduplication, where used, always tells the user
   what happened (ADR-008).
6. **Peak-day and other derived quantities are calculated, not assumed**
   — no hard-coded day-0 shortcuts survive into the new key-day dataset
   builder, even though the current model is expected to keep finding
   day 0 (ADR-009).
7. **The validated calculation engine's semantics are out of scope.**
   Every decision above concerns architecture around the engine, not the
   engine's equations. Any implementation task that would touch
   calculation semantics stops for explicit human approval.

## 6. Decision-to-specification map

| Area | ADR(s) | Detailed in |
|---|---|---|
| Top-level unit, terminology, folder structure | ADR-001, ADR-002, ADR-003 | `folder_and_input_schema.md` |
| Assumption sets, use patterns | ADR-004, ADR-005 | `folder_and_input_schema.md` |
| GUI editing mechanism, save behaviour | ADR-006, ADR-007 | `run_lifecycle_and_validation.md` |
| Run lifecycle, deduplication | ADR-008 | `run_lifecycle_and_validation.md` |
| Raw + key-day result persistence | ADR-009 | `result_architecture_and_aggregation.md` |
| Reporting groups, aggregation | ADR-010, ADR-011 | `result_architecture_and_aggregation.md` |
| Table architecture | ADR-012 | `table_and_figure_architecture.md` |
| Figure architecture | ADR-013 | `table_and_figure_architecture.md` |
| Shiny navigation | ADR-014 | `shiny_information_architecture.md` |
| Migration | ADR-015 | `migration_plan.md` |
| Implementation phasing | ADR-016 through ADR-020 amend the approved phasing; the phasing itself is Decision 16 / Q004, **resolved** | `implementation_phases_proposal.md` |
| Table 162 support: deferred, source preserved | ADR-016 | `migration_plan.md`, `implementation_phases_proposal.md` §"Deferred capabilities and legacy retirement" |
| Sensitivity analysis: deferred | ADR-017 | `implementation_phases_proposal.md` §"Deferred capabilities and legacy retirement" |
| Source-document provenance (4-tier model) | ADR-018 | `migration_plan.md` §0, `reproducibility_and_provenance.md` §2.8, `folder_and_input_schema.md` §1.1 |
| Independent-review policy (risk-based) | ADR-019 | `implementation_phases_proposal.md` §"Independent-review policy application", `invariants_and_test_plan.md` §3 |
| Legacy Shiny app retirement checkpoint | ADR-020 | `implementation_phases_proposal.md` §"Deferred capabilities and legacy retirement" |

## 7. What remains genuinely open

Tracked in `docs/planning/unresolved_questions.md`. As of this session,
**Q004 through Q009 are resolved** (implementation phasing approved with
amendments; old app/figure-batch fate; Table 162/Sensitivity disposition;
independent-review policy; source-document provenance model — see
ADR-016 through ADR-020). Two questions remain genuinely open, neither
blocking:
- **Q002** — whether `data/reference/` itself needs multi-set support, or
  set variety only emerges once evaluations exist.
- **Q003** — whether user-requested custom days get added retroactively
  to a run's persisted key-day dataset, or are always a separate
  on-demand query.

Neither blocks Phase 0; both are revisited at the implementation-time
points already noted in `unresolved_questions.md`.
