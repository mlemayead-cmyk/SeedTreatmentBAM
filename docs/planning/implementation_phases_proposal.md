# Implementation phases — proposal

**Status: APPROVED, with the amendments below.** This addresses Decision
16 / Q004 (`docs/planning/unresolved_questions.md`). The 8-phase (0–7,
with 6a/6b) skeleton was reviewed in
`docs/planning/implementation_readiness_review.md` (verdict: READY WITH
MINOR PHASING CHANGES) and approved by the user with the amendments
incorporated below — no phase is merged, dropped, or reordered; the
changes are additive tickets, expanded gates, internal sequencing
constraints within Phase 1/3, and two new cross-cutting sections (§"Deferred
capabilities and legacy retirement," §"Independent-review policy
application"). See ADR-016 through ADR-020
(`assessment_workspace_architecture.md`) for the decisions behind these
amendments.

**Still required before Phase 0 implementation begins**: nothing
blocking — see `implementation_readiness_review.md` §9 for the full
non-blocking checklist (naming conventions, Q002/Q003, etc.), all
confirmed non-blocking.

**Every phase below:**
- is independently testable against explicit invariants from
  `invariants_and_test_plan.md`;
- is reviewable (by the user, or an independent review pass) before the
  next phase starts;
- preserves the currently-validated calculation engine unchanged, unless
  a step is explicitly flagged **SCIENTIFIC MODEL CHANGE — HUMAN APPROVAL
  REQUIRED** (none are, in this proposal);
- includes its own tests, run against the existing `tests/testthat/`
  suite plus new tests specific to that phase;
- is sized for an AI coding agent to implement from this specification
  plus its own targeted ADR references, with an independent review pass
  before merge — consistent with the review discipline already used
  earlier in this project (`docs/independent_engine_audit.md`,
  `docs/max_obtainable_exposure_review.md`).

---

## Phase 0 — Shared infrastructure utilities

**Scope:** two small, standalone utilities identified as needed by later
phases, buildable and testable in isolation first.
1. **Peak-finder utility** (`result_architecture_and_aggregation.md` §2):
   given a day-dependent function and a scenario/receptor/metric/diet-
   fraction context, returns the argmax day. Tested against both the
   current (monotonic) model behaviour and a synthetic non-monotonic test
   case (I9).
2. **Content-hash/canonicalization utility** (`run_lifecycle_and_validation.md`
   §2): deterministic hash over a set of input files. Tested for
   stability across repeated calls with logically-identical input,
   regardless of file-write order (I5, I10).

**Gate before Phase 1:** both utilities pass their unit tests in
isolation; no other code depends on them yet.

**Scientific-safety caution (confirmed this session):** the peak-finder
utility establishes an architectural capability — "peak is a calculated
argmax, not permanently synonymous with day 0" — it does **not** alter
the currently-validated exposure equations or the current model's
scientific behaviour. For the current, independently-audited model, the
correct, expected result of the peak-finder is very likely still day 0
in every case (the model's monotonic decline is independently verified,
`docs/independent_engine_audit.md`) — a peak-finder that returns day 0
for the current model is not a defect and must not be second-guessed or
"corrected" toward a different answer merely because a general search
mechanism was expected to find something more interesting. The synthetic
non-monotonic test case (I9) exists to prove the mechanism is general,
not to imply the current model's own result should differ from day 0.
This ticket touches no file under `R/calculations/`.

**Independent review (ADR-019):** mandatory for this ticket (category 1
— "peak/key-day calculation logic where scientific result semantics are
involved").

## Phase 1 — Folder and input schema, GUI editing, validation

**Scope:** `folder_and_input_schema.md` in full — evaluation folder
creation, named-set folders and manifests, `use_patterns.csv`, validation
schemas, the Shiny grid/form/Excel-round-trip editing mechanism
(`shiny_information_architecture.md` §3), and per-table/whole-evaluation
save behaviour (`run_lifecycle_and_validation.md` §1). Also: the
evaluation picker/landing screen (`shiny_information_architecture.md`
§2), since it only depends on the folder schema, not on runs/results.

**Explicitly excluded from this phase:** runs, raw/grouped results,
tables, figures — an evaluation created in this phase has valid, editable
inputs and nothing else yet.

**Tickets (illustrative, to be refined at implementation time):**
1. Evaluation folder creation logic + picker screen Create/Open/Clone/
   Rename/Delete actions.
2. Named-set folder/manifest read-write logic, one category at a time
   (agronomy, receptors, effects, fate, reporting).
3. `use_patterns.csv` read-write logic with normalized-row semantics.
4. Validation schema definitions per table (columns/types/permitted
   values/referential integrity/uniqueness/range).
5. Shiny grid (`DT`) + add/edit form/modal per editable table.
6. Excel export (`writexl`) / import (`readxl`) with validate-before-
   replace behaviour.
7. Per-table Save + whole-evaluation Save-all, with dirty-state tracking.

**Gate before Phase 2:** I1, I3, I15 pass; a hand-created evaluation
folder can be opened, edited, validated, and saved end-to-end in Shiny
with no run/result functionality yet.

**Recommended internal sequencing (from the readiness review, not a
change to this phase's overall gate):** build and get reviewed one full
assumption category end-to-end first — recommend `seeding_sets`, since it
is migration's most-used category — schema, manifest, grid, form, Excel
round-trip, save, all working and reviewed as a template — before
replicating the pattern to the remaining four categories
(`receptor_sets`, `effects_sets`, `fate_sets`, `reporting_sets`). This
reduces the risk of discovering a schema design flaw only after all five
categories have already been built.

**Independent review (ADR-019):** not required category-wide (this phase
is predominantly GUI/plumbing); escalate per-ticket only if
implementation evidence raises a specific concern.

## Phase 2 — Migration

**Scope:** `migration_plan.md` in full (revised this session — corrected
input inventory, added adapter ticket, expanded gate). Depends on Phase
1's folder/input schema being implemented and stable.

**Tickets:**
1. `scenario_definitions.csv` -> `use_patterns.csv` transformation +
   unit tests (multi-planting-method case, full-dataset coverage).
2. Named-set population from `data/reference/*.csv` + manifest population
   with provenance (reusing existing SHA-256/audit-trail data where
   available), **including tier-1 provenance metadata** (path + verified
   SHA-256 for the 6 original workbooks and the Table 162 source Word
   document — `migration_plan.md` §0.1/§2.1; the originals themselves are
   never copied into the evaluation).
3. **Tier-3 provenance-file copy**: `source_manifest.csv`,
   `review_core_assumptions.csv`, `review_effects_metrics.csv`,
   `table162_considerations.csv`, `table162_decision_matrix.csv`,
   `copied_register_manifest.csv` into `inputs/reference/`, unchanged,
   SHA-256 verified (`migration_plan.md` §2.3). *(Newly added this
   session — previously missing from this phase's scope.)*
4. **`STBAM_WORKBOOK_TO_CROP_FAMILY` extraction** into an initial
   `reporting_sets/crop_family.csv` (`migration_plan.md` §2.4, ADR-010,
   ADR-016). *(Newly added this session.)*
5. **Evaluation-inputs → engine-parameter-set adapter**
   (`migration_plan.md` §3 step 4). *(Newly added this session — this is
   the dependency-ordering fix identified by the readiness review: the
   verification ticket below cannot run without it, so it is built here,
   in Phase 2, not deferred to Phase 3's "raw-result computation wiring,"
   which reuses this adapter unchanged rather than rebuilding it.)*
6. End-to-end migration script (tickets 1-4 composed).
7. Verification: the full 9-point gate below, using ticket 5's adapter to
   feed the migrated evaluation's inputs through the **unchanged** engine.

**Gate before Phase 3:** all 9 points of `migration_plan.md` §4 pass —
not merely "the evaluation folder and input files can be created." In
summary: exact `scenario_inputs`/`scenario_summary` match against current
canonical outputs (I11); hard-coded row-count assertions; tier-3
provenance-file completeness (SHA-256 verified); lossless named-set copy;
crop-grouping data carried forward; no crop-count truncation regression;
existing test suite passes unmodified (I16); migration is re-runnable.
The migrated evaluation also opens and edits correctly in the Phase 1
GUI.

**Explicitly not required for this gate (ADR-016, ADR-017):** Table 162
Shiny-module parity; Sensitivity-tab parity. Their source data is
preserved (tickets 3-4 above); their redesign is a separate, later
checkpoint — see "Deferred capabilities and legacy retirement" below.

**Independent review (ADR-019):** mandatory for tickets 5 (adapter) and 7
(migration-equivalence verification) — categories 2 and 3. Tickets 1-4
and 6 follow the standard human-review gate; escalate individually only
if a specific concern arises.

**Decision resolved this session (ADR-020):** the current override-based
Shiny app's fate is **not** decided at this phase gate. Completing Phase
2 does not authorize retiring the legacy app — see "Deferred capabilities
and legacy retirement" below for the actual checkpoint.

## Phase 3 — Run lifecycle and raw results

**Scope:** `run_lifecycle_and_validation.md` (run creation, deduplication,
`run_manifest.csv`) + `result_architecture_and_aggregation.md` §1-3 (raw
`scenario_inputs`/`scenario_summary` per run, `key_day_results`, on-demand
full daily time course). Uses Phase 0's peak-finder and content-hash
utilities, and **reuses Phase 2's evaluation-inputs → engine-parameter-set
adapter unchanged** (`migration_plan.md` §3 step 4) — this phase does not
rebuild that logic. Runs screen in Shiny
(`shiny_information_architecture.md` §4).

**Tickets:**
1. `inputs_snapshot/` freezing logic.
2. Content-hash-based dedup check + explicit user prompt on match.
3. Raw-result computation wiring — calls the **unchanged** engine via
   Phase 2's adapter (ticket 5 of that phase), not a new adapter.
4. `key_day_results` builder, using the Phase 0 peak-finder for
   `day_label = "peak"`.
5. On-demand full daily-time-course generation, scoped (bounded) request
   interface.
6. `run_manifest.csv` writer with all required provenance fields
   (`reproducibility_and_provenance.md` §2.2).
7. Runs screen: list, create, select-active-run.

**Recommended internal sequencing:** build tickets 1-3 and a minimal
version of ticket 6 (hash + dedup + raw `scenario_inputs`/`scenario_summary`
write + minimal manifest) first, get that reviewed end-to-end, before
adding `key_day_results` (ticket 4), on-demand generation (ticket 5), and
the full Runs screen (ticket 7).

**Gate before Phase 4:** I2, I4, I5, I9, I10, **and I17** pass (I17 added
this session — `run_manifest.csv`, ticket 6, is exactly the artifact I17
governs for runs; it was previously untested until Phase 5 by omission);
a run can be created from the migrated evaluation, reproduces expected
raw results, and repeated identical runs are correctly deduplicated with
explicit user notice.

**Independent review (ADR-019):** mandatory for tickets 1-2 (category 4 —
"run freezing/persistence and reproducibility") and ticket 4 (category 1
— peak/key-day calculation logic). Tickets 5-7 follow the standard human-
review gate.

## Phase 4 — Reporting groups and grouped results

**Scope:** `result_architecture_and_aggregation.md` §4-8 (reporting-scheme
schema, `grouped_results`, `grouped_result_bounds`, deterministic tie
handling, drill-down data path).

**Tickets:**
1. `reporting_sets` scheme schema + validation (crop-only, partial
   coverage, singleton groups allowed) — extends Phase 1's validation
   mechanism.
2. Grouped-result computation: range + bound identity + counts.
3. Tie detection + `grouped_result_bounds` companion table +
   deterministic representative selection (documented rule).
4. Results screen: grouped/individual/raw browsing
   (`shiny_information_architecture.md` §5), reusing bound identity for
   drill-down.

**Gate before Phase 5:** I6, I7, I8 pass; a grouped view over the migrated
evaluation's first run produces correct ranges, correctly identifies tied
bounds, and correctly rejects a scheme that attempts to group by a
non-crop dimension. Confirm the migrated `reporting_sets/crop_family.csv`
(Phase 2 ticket 4) validates cleanly as the first real-world exercise of
this phase's schema.

**Independent review (ADR-019):** mandatory for ticket 2 (grouped-result
computation) and ticket 3 (tie detection) — category 5, "aggregation/
range logic and min/max bound traceability." Ticket 1 (schema/validation)
and ticket 4 (Results screen) follow the standard human-review gate.

## Phase 5 — Table architecture

**Scope:** `table_and_figure_architecture.md` §1-3 (shared definition/
live-render/export pattern, table definitions, table export).

**Tickets:**
1. Table definition schema + storage.
2. Live recomputation of a table's values from its `run_id` + grouped/raw
   results.
3. Export action (CSV/XLSX/Word) with full provenance metadata
   (`reproducibility_and_provenance.md` §2.3-2.4).
4. Tables screen (`shiny_information_architecture.md` §6).
5. Reporting/table-builder version identifier, introduced here.

**Gate before Phase 6:** I12, I13, I14, I15 (table-specific), I17
(table provenance) pass.

**Independent review (ADR-019):** not individually mandatory for this
phase's tickets (definition/export plumbing, not scientific-semantics or
aggregation logic) — escalate per-ticket only if a specific concern
arises.

## Phase 6 — Figure architecture

**Scope:** `table_and_figure_architecture.md` §4-6 (figure definitions,
level-of-detail x series model, envelope semantics, drill-down, export).
Larger and more complex than Phase 5 (per
`implementation_dependencies_and_risks.md` §3) — proposed as two
sub-phases:

**Phase 6a — Grouped detail level only.** Directly replaces the highest-
value use case of the current static batch-figure output.
1. Figure definition schema + storage.
2. Grouped-envelope rendering (min-max band), with mandatory bound-
   ambiguity footnote.
3. Bound-identity drill-down affordance (click/hover an envelope edge).
4. Series support at the grouped level (multiple envelopes in one
   figure — e.g. comparing assumption sets).
5. Export, with figure-builder version identifier introduced here.

**Phase 6b — Individual and raw detail levels.**
1. Individual-level rendering + series selection UX (multi-select,
   "drivers of the envelope" shortcut, focal-crop shortcut).
2. Raw-level rendering + scenario-ID selection, reachable via drill-down.
3. Soft unreadability warnings for large/unusual selections.
4. Full switching between all three levels within one figure.

**Gate before Phase 7 (or before considering Phase 6 complete):** I12,
I13, I14, I15 (figure-specific), I17 (figure provenance) pass; the
envelope-ambiguity footnote is present on every grouped figure; Phase 6a
alone is usable end-to-end even if 6b slips. **Phase 7's own gate only
requires Phase 6a's capabilities as a hard blocker** — 6b enhances but
does not gate Phase 7's walkthrough if it has slipped (see Phase 7 below).

**Decision resolved this session:** the existing ~581-file, ~200MB static
figure batch under `outputs/figures/` is **archived, not deleted**, once
the new figure architecture (6a) demonstrates it covers the batch's
primary use cases — it remains a useful before/after reference (it is
the only artifact set in this project's history with a fully independent
SHA-256/existence/visual check, `PROJECT_STATE.md`). Decision timing
(after Phase 6a demonstrates coverage, not before) is unchanged from the
original proposal.

**Independent review (ADR-019):** mandatory for 6a ticket 2 (grouped-
envelope rendering) — category 6, "grouped/time-dependent envelope
calculations." Mandatory for 6b's series-selection/multi-run comparison
work — category 7, "figure traceability where multiple runs/assumption
sets are compared." Remaining tickets in both sub-phases (definition
schema, export plumbing, UX controls) follow the standard human-review
gate.

## Phase 7 — Full Shiny workspace integration

**Scope:** the remaining pieces of `shiny_information_architecture.md`
not already delivered incrementally alongside Phases 1-6 (each phase
above already includes its own screen(s)) — primarily end-to-end
navigation polish, cross-screen "which run is active" consistency, and
any remaining cross-cutting UI requirements (§8 of that specification).

**Gate:** full manual acceptance walkthrough — create an evaluation,
edit inputs, run, view grouped/individual/raw results, build and export a
table, build and export a figure, switch evaluations via the picker —
without leaving the app. **This walkthrough requires only Phase 6a's
figure capabilities as a hard blocker; if Phase 6b (individual/raw
detail levels, series selection) has slipped, the walkthrough still
passes using grouped-level figures, and 6b is completed as a follow-on
without re-gating Phase 7.**

**Scope boundary, confirmed this session:** this walkthrough does **not**
exercise Table 162 support or Sensitivity — neither is scoped anywhere in
Phases 0-7 (ADR-016, ADR-017). Passing Phase 7's walkthrough is not a
claim of full feature parity with the legacy app; see "Deferred
capabilities and legacy retirement" below for what remains outstanding
after Phase 7.

**Independent review (ADR-019):** not individually mandatory (navigation/
polish work); the walkthrough itself is the phase's review mechanism.

## 7a. Deferred capabilities and legacy retirement (new this session)

Two capabilities present in the current, validated application are
**deliberately deferred, not dropped, and not scoped to any phase
0-7 ticket** (ADR-016, ADR-017):

- **Table 162 support** — the current `R/summaries/24_table162_support.R`
  / `mod_table162_*` Shiny module. Its source data (the copied
  `table162_*`/`review_*` registers, plus `STBAM_WORKBOOK_TO_CROP_FAMILY`
  extracted into an initial `reporting_sets/` scheme) is preserved through
  migration (Phase 2, tickets 3-4). Its actual upstream source is the
  assessment Word document
  (`THE BAM ST RA - interim draft TABLES and FIGS - LIVE.mdlAug26.docx`,
  sibling project), not the copied CSV registers — a future redesign
  should be grounded in that document's own structure, not merely in the
  current R implementation. A dedicated redesign checkpoint is created,
  not scheduled to a specific phase number — to be planned once Phases
  1-5 (evaluation/run/reporting-group architecture) are stable.
- **Sensitivity analysis** — the current `R/shiny/42_module_sensitivity.R`
  one-at-a-time override-based sweep. Reconsidered only after the named
  assumption-set (Phase 1), preserved-run (Phase 3), and multi-run/multi-
  set comparison (Phase 6, via ADR-013's series dimension) capabilities
  are working — at that point the live question becomes whether complete-
  set/run comparison already subsumes the need, not how to port the
  existing tab. No phase number assigned.

**Legacy Shiny application retirement (ADR-020):** no phase gate 0-7
authorizes retiring the current override-based Shiny application.
Informal user guidance may shift toward the new app once Phase 2
(migration) is complete, but **formal retirement is decided at a
dedicated later checkpoint**, reached only once (a) Phase 7's full
walkthrough passes, and (b) Table 162 support and Sensitivity have each
reached their own explicit disposition — redesigned with demonstrated
parity, or explicitly, separately decided as permanently legacy-only. No
legacy feature is retired merely because it was absent from Phases 0-7's
scope.

## 7b. Independent-review policy application (new this session, ADR-019)

Every ticket in every phase gets: automated tests, explicit acceptance
criteria, and a human review/approval gate. **Independent adversarial
agent review is additionally mandatory** only for tickets falling into
one of these categories (marked per-phase above):

1. Peak/key-day calculation logic (Phase 0 peak-finder; Phase 3
   `key_day_results`).
2. The evaluation-inputs → engine-parameter-set adapter (Phase 2).
3. Migration equivalence (Phase 2's full gate).
4. Run freezing/persistence and reproducibility (Phase 3
   `inputs_snapshot`/dedup).
5. Aggregation/range logic and min/max bound traceability (Phase 4).
6. Grouped/time-dependent envelope calculations (Phase 6a).
7. Figure traceability across multiple runs/assumption sets (Phase 6b).

Routine GUI/layout/plumbing tickets (the bulk of Phases 1, 5, and parts
of 3/4/6) do not individually require independent review unless
implementation evidence raises a specific concern for that ticket.

## 8. Summary table

| Phase | Depends on | Key invariants proven |
|---|---|---|
| 0 | — | I9 (partial), I5 (partial) |
| 1 | Phase 0 (not strictly required) | I1, I3, I15 |
| 2 | Phase 1 | I11 |
| 3 | Phases 0-2 | I2, I4, I5, I9, I10, **I17** |
| 4 | Phase 3 | I6, I7, I8 |
| 5 | Phase 4 | I12, I13, I14, I15, I17 |
| 6a | Phase 4 (can start alongside Phase 5) | I12, I13, I14, I15, I17 |
| 6b | Phase 6a | I12, I13, I14, I15, I17 (extended) |
| 7 | Phases 1-6 | Full manual acceptance walkthrough |

I16 (engine untouched) is a standing check applied to every phase, not
tied to one phase's gate.

## 9. Approval record

**Resolved this session** (previously open questions in this section):
- Phase 6's 6a/6b split — approved as proposed (§ Phase 6a/6b above).
- Old override-based app's fate — resolved via ADR-020: not retired at
  any single phase gate; formal retirement decided at a dedicated later
  checkpoint (§7a above).
- Old static figure batch's fate — resolved: archived (not deleted) once
  Phase 6a demonstrates coverage (§ Phase 6a/6b above).
- Independent-review gate scope — resolved via ADR-019: risk-based,
  mandatory for the 7 named categories in §7b, not for every ticket and
  not only at whole-phase boundaries.
- Table 162 support and Sensitivity's absence from Phases 0-7 — resolved
  via ADR-016/ADR-017: both explicitly deferred, source data preserved
  through migration, legacy modules kept available, dedicated future
  redesign checkpoints created (§7a above).
- The evaluation-inputs → engine-parameter-set adapter's phase placement
  — resolved: moved into Phase 2 (ticket 5 of that phase), reused
  unchanged by Phase 3, closing the dependency gap the readiness review
  identified.

No production-code implementation begins until Phase 0 is explicitly
authorized in a future session — this document's approval covers the
phasing and gates, not a green light to start writing code.
