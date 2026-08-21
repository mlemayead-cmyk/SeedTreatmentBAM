# Implementation readiness review — `stbam` redesign

**Resolution status (updated the same session, after user review):** the
user approved the READY WITH MINOR PHASING CHANGES verdict and the
8-phase skeleton, and resolved every recommendation below plus several
additional gaps found during that resolution (source-location
verification, Table 162/Sensitivity disposition). See ADR-016 through
ADR-020 in `assessment_workspace_architecture.md` for the resulting
decisions, and `migration_plan.md`, `implementation_phases_proposal.md`,
`folder_and_input_schema.md`, `implementation_dependencies_and_risks.md`,
`invariants_and_test_plan.md`, `reproducibility_and_provenance.md`,
`architecture_specification.md`, and `unresolved_questions.md` for where
each recommendation was incorporated. **This document is left unedited
below as the point-in-time review that prompted those decisions** — read
the documents above for the current, authoritative state.

**Purpose:** an independent readiness/phasing review of
`docs/planning/implementation_phases_proposal.md` against the accepted
ADR log (`assessment_workspace_architecture.md`, ADR-001–ADR-015) and its
nine companion specifications, before Phase 0 is authorized.

**Method:** every document under `docs/planning/` was read in full, plus
`PROJECT_STATE.md`, `README.md`, `docs/current_implementation_inventory.md`,
`docs/developer_guide.md`, `docs/model_validation_report.md`'s verdict
section, and `docs/scientific_model_specification.md`'s table of
contents. Selected claims (hard-coded `peak_rq_day <- 0`,
`STBAM_WORKBOOK_TO_CROP_FAMILY`, the daily-timecourse "gigabyte" comment)
were independently spot-checked against the live source under `R/`.
**No production file was modified to produce this document** — only this
file was created.

---

## 1. Overall verdict

**READY WITH MINOR PHASING CHANGES.**

The eight-phase (0–7, with 6a/6b) structure is dependency-correct at the
phase-boundary level, each phase has an explicit, testable gate tied to
named invariants, and every phase preserves `R/calculations/*.R`
unchanged with no step requiring **SCIENTIFIC MODEL CHANGE — HUMAN
APPROVAL REQUIRED** treatment. It should be approved in substance.

It is not yet ready to hand to a coding agent unmodified, for four
concrete, fixable reasons detailed below (§3, §7):

1. **A real dependency-ordering gap**: the migration-equivalence gate
   (Phase 2) requires an "evaluation inputs → engine parameter set"
   adapter that no ticket explicitly builds until Phase 3. Phase 2 cannot
   pass its own gate without a piece of infrastructure the proposal
   schedules one phase later.
2. **A migration-plan input-inventory gap**: the migration script's
   stated inputs (`data/reference/*.csv` categories +
   `scenario_definitions.csv`) omit the read-only provenance files
   (`source_manifest.csv`, both `review_*.csv`, both `table162_*.csv`,
   `copied_register_manifest.csv`) and, more importantly, omit the
   **only existing crop-grouping data in the codebase**
   (`STBAM_WORKBOOK_TO_CROP_FAMILY`, a hard-coded R constant, not a CSV) —
   exactly the thing ADR-010 is designed to replace with an editable
   `reporting_sets/` scheme.
3. **Two current, validated Shiny capabilities — the "Table 162 support"
   tab and the "Sensitivity" tab — are not mentioned anywhere across all
   twelve planning documents.** Not deferred, not declared out of scope:
   absent. This needs an explicit decision, not silent expectation that
   Phase 7 "polish" will somehow cover it.
4. **Phase 1 is sized as one gate covering five assumption categories'
   full CRUD + validation + Excel round-trip.** Its own ticket list (7
   items) already shows this is really an epic; the phase-level gate
   should require a vertical slice (one category end-to-end) before
   fanning out to the remaining four, not because the dependency order is
   wrong, but because discovering a schema design flaw after building all
   five categories is expensive to unwind.

None of these invalidate the phase skeleton itself. They are the kind of
finding a readiness review exists to catch before an AI agent starts
implementing against an under-specified gate.

---

## 2. ADR/spec consistency

Spot-checks confirmed the ADR log accurately describes current code
(`peak_rq_day <- 0` at `R/summaries/23_scenario_summary.R:42`;
`STBAM_WORKBOOK_TO_CROP_FAMILY` at `R/summaries/24_table162_support.R:11`;
the "on the order of a gigabyte" comment at
`scripts/build_canonical_outputs.R:52`). The companion specifications are
faithful, readable restatements of their source ADRs — no drift found
between `architecture_specification.md` and the ADR log itself.

Concrete gaps/ambiguities found:

- **Table 162 support and Sensitivity are unaddressed** (§1 item 3, §6
  below). This is the most significant consistency gap: it affects
  scope for `shiny_information_architecture.md`, the migration plan's
  input inventory, and possibly the reporting-group schema (ADR-010),
  since `STBAM_WORKBOOK_TO_CROP_FAMILY` is Table 162 support's own
  crop-grouping logic and is the natural seed for a migrated
  `reporting_sets/crop_family.csv`.
- **Migration plan's input inventory is incomplete relative to
  `folder_and_input_schema.md` §1's own `inputs/reference/` destination.**
  `folder_and_input_schema.md` correctly describes a `reference/` folder
  for "source manifests, Table 162 registers, SHA-256 audit records;" but
  `migration_plan.md` §2's "Inputs to the migration script" only lists
  the 7 assumption-category CSVs + `scenario_definitions.csv` — it never
  enumerates copying `source_manifest.csv`, `review_core_assumptions.csv`,
  `review_effects_metrics.csv`, `table162_considerations.csv`,
  `table162_decision_matrix.csv`, or `copied_register_manifest.csv` into
  the new evaluation's `inputs/reference/`. The destination is specified;
  the source step is not.
- **I2's "outputs/ always fully regenerable" is underspecified for
  exports.** `run_lifecycle_and_validation.md` and
  `table_and_figure_architecture.md` are explicit that table/figure
  *exports* are deliberately frozen and must **not** silently regenerate
  or change (I13). `invariants_and_test_plan.md`'s test for I2 ("delete
  `outputs/`, regenerate from `inputs/`, compare exactly") doesn't state
  whether it covers the full `outputs/` tree (including
  `tables/exports/`, `figures/exports/`) or only the deterministically
  regenerable computational layers (`runs/*/raw_results`,
  `grouped_results`). As written, a literal "delete `outputs/` and
  regenerate" test would either have no way to reproduce a deleted export
  (by design — I13), or would need to special-case exports out of I2's
  scope. Recommend narrowing I2's wording to explicitly exclude
  `tables/exports/` and `figures/exports/` (which are non-regenerable by
  design) and confirming it covers `runs/`, `grouped_results/`, and table/
  figure **definitions** (which are regenerable/re-viewable, unlike
  exports).
- **I15's literal wording doesn't cover table/figure definitions**, but
  `implementation_phases_proposal.md`'s Phase 5/6a/6b gates cite "I15
  (table-specific)" — a reasonable generalization of the principle
  ("failed validation never replaces a previously saved, valid file") but
  one the invariant's own text (scoped to "GUI edit or Excel/CSV import"
  of `ADR-006` input files) doesn't literally state. Minor; recommend
  either broadening I15's wording or explicitly noting the generalization
  in `invariants_and_test_plan.md`.
- **I17 (provenance) is not gated at Phase 3**, even though Phase 3
  ticket 6 is exactly what produces `run_manifest.csv`, the artifact I17
  governs for runs. The phases' invariant-coverage summary table
  (`implementation_phases_proposal.md` §8) assigns I17 only to Phases
  5/6a/6b (table/figure provenance), leaving run provenance completeness
  untested until much later by omission. See §4 matrix below.

No conflicts were found where an implementation phase actually
contradicts an Accepted ADR's substance (i.e., nothing in the proposal
tries to quietly reinterpret a decision to make it easier to build). The
issues above are gaps and sequencing problems, not architectural
disagreements.

---

## 3. Phase-by-phase assessment

| Phase | Purpose | Dependencies | Testable independently? | Main risks | Recommendation |
|---|---|---|---|---|---|
| **0** — Shared utilities (peak-finder, content-hash) | Small, standalone infrastructure used by later phases | None | Yes — pure-function unit tests, no other code depends on them yet | Peak-finder is calculation-adjacent (reads engine output); must not migrate into `R/calculations/` or be perceived as changing model semantics | **Endorse as-is.** Recommend this be the literal first ticket (see §8) — smallest, most scientifically sensitive, best canary for the review discipline the rest of the project depends on. |
| **1** — Folder/input schema, GUI editing, validation, picker | Evaluation folder creation + 5 assumption categories' CRUD/validation/Excel round-trip + `use_patterns.csv` + save mechanics + picker screen | Phase 0 (soft) | Yes, at the ticket level; the phase-level gate bundles 7 tickets into one all-or-nothing review point | Largest phase by surface area; a schema design flaw found on category 4 or 5 requires reworking categories 1–3 too if built in parallel/batch | **Split execution, not scope**: build one category (recommend `seeding_sets`, since it is the migration's most-used category) end-to-end first — schema, manifest, grid, form, Excel round-trip, save — as a template, get it reviewed, *then* replicate the pattern to `receptor_sets`, `effects_sets`, `fate_sets`, `reporting_sets`. Keep the phase's overall gate as proposed, but treat "one category proven" as an internal checkpoint before fanning out. |
| **2** — Migration | Convert current project into first evaluation; verify equivalence | Phase 1 | Yes — the migration-equivalence gate (§5) is concrete and automatable | (a) **Missing adapter dependency** — the verification step needs a way to feed migrated `inputs/` into the *unchanged* engine, but that adapter is Phase 3's "raw-result computation wiring" ticket, not any Phase 1/2 ticket. (b) Input-inventory gap (§2) — provenance files and `STBAM_WORKBOOK_TO_CROP_FAMILY` are not in migration's stated inputs. (c) Table 162 support / Sensitivity scope undecided (§6) | **Add an explicit Phase 2 ticket**: "minimal evaluation → engine-parameter-set loader," built once, reused by both the migration-equivalence check (Phase 2) and the full run lifecycle (Phase 3) — do not let Phase 2's gate depend on unscheduled Phase 3 work. **Add to migration script scope**: copy the 6 provenance-only files into `inputs/reference/` unchanged (with SHA-256 check); extract `STBAM_WORKBOOK_TO_CROP_FAMILY` into an initial `reporting_sets/crop_family.csv`. **Decide Table162/Sensitivity fate before this phase starts** (§6), since it affects whether migration needs to carry the crop-family mapping at all. |
| **3** — Run lifecycle, raw results | `inputs_snapshot`, dedup, raw-result computation, `key_day_results`, on-demand daily time course, `run_manifest.csv`, Runs screen | Phases 0–2 | Yes — I2/I4/I5/I9/I10 all concretely testable | Moderately large (7 tickets); the evaluation→engine-parameter-set adapter (see Phase 2 row) should already exist by the time this phase starts, not be built fresh here | **Build the vertical slice first**: hash + dedup + raw `scenario_inputs`/`scenario_summary` write + minimal manifest, get that reviewed, before adding `key_day_results`/on-demand generation/Runs-screen polish. **Add I17 to this phase's gate** (run-manifest provenance completeness) — currently only tested at Phase 5+ for tables/figures, never for runs themselves. |
| **4** — Reporting groups, grouped results | `reporting_sets` schema, `grouped_results`, `grouped_result_bounds`, tie handling, Results screen | Phase 3 | Yes — I6/I7/I8 map directly to concrete schema/contract tests | Low — well-specified, ADR-010/011 leave little ambiguity | **Endorse as-is.** If Table162's crop-family mapping is ported (§6), confirm its migrated `reporting_sets/crop_family.csv` (from Phase 2) validates cleanly against this phase's schema as the first real-world exercise of it. |
| **5** — Table architecture | Definition/live-render/export pattern for tables | Phase 4 | Yes — I12/I13/I14/I15/I17 | Low — directly modelled on ADR-012, which is unambiguous | Endorse as-is. |
| **6a** — Figures, grouped detail only | Figure definitions, grouped-envelope rendering, bound-identity drill-down, export | Phase 4 (can start alongside Phase 5) | Yes — same invariant set as tables, plus the mandatory envelope-ambiguity footnote | "Can proceed in parallel with Phase 5" requires actual worktree isolation per the stated AI-workflow model (§12 of the review brief) — the proposal doesn't say this explicitly | Endorse the 6a/6b split (this is the single clearest scope-reduction win in the whole proposal — it isolates the highest-value replacement for the current static batch). **State explicitly** that "parallel with Phase 5" means two separate agent sessions on two worktrees, not concurrent edits to one tree, consistent with the stated no-simultaneous-editing rule. |
| **6b** — Figures, individual/raw detail | Series selection UX, raw drill-down, full level-switching | Phase 6a | Yes — extended invariant set | Larger UX surface (multi-select, shortcuts, soft warnings) with more implementation-time judgement calls than most other phases | Endorse as-is; explicitly allowed to slip without blocking Phase 7's *usability*, but Phase 7's gate (full walkthrough) does implicitly require it — flag this tension (§3 note below). |
| **7** — Full Shiny workspace integration | Navigation polish, cross-screen "active run" consistency, full walkthrough | Phases 1–6 | Yes — full manual acceptance walkthrough is a clear, if coarse, gate | The walkthrough as described ("create an evaluation, edit inputs, run, view results, build/export a table, build/export a figure, switch evaluations") **does not exercise Table 162 support or Sensitivity at all**, because neither is scoped anywhere. If either is expected to exist in the new app, Phase 7 is not actually a completion gate for the redesign as a whole. | **Do not let this phase silently absorb a Table162/Sensitivity port.** If either is in scope, it needs its own phase (with its own ADR for the reporting-group question above), scheduled explicitly, not discovered during Phase 7 acceptance testing. |

**Cross-phase note on Phase 6b/Phase 7 tension**: Phase 6's own gate text
says "Phase 6a alone is usable end-to-end even if 6b slips," which is
good — but Phase 7's gate is a full walkthrough that includes figure
work without qualifying which detail level is required. Recommend Phase
7's gate explicitly state it only requires 6a's capabilities as a hard
blocker, with 6b treated as enhancing (not gating) the walkthrough if it
has slipped.

---

## 4. Invariant coverage matrix

| Invariant | Established in | Tested in | Continues to be guarded? | Concern |
|---|---|---|---|---|
| I1 — `inputs/` always complete, never override | Phase 1 | Phase 1 | Yes, structurally (no later phase reintroduces override semantics) | None |
| I2 — `outputs/` fully regenerable from `inputs/` + `model_version` | Phase 3 (raw layer) | Phase 3 | Partially — see §2. Grouped results (Phase 4) and definitions (Phase 5/6) extend the regenerable set; **exports do not and should not** | Wording ambiguity: does I2 cover `tables/exports/`/`figures/exports/`? It should not (conflicts with I13). Recommend narrowing I2's stated scope explicitly. |
| I3 — Updating `data/reference/` never retroactively alters an evaluation | Phase 1 | Phase 1 | Yes, structurally | None |
| I4 — Run's `inputs_snapshot/` immutable to later named-set edits | Phase 3 | Phase 3 | Yes | None |
| I5 — Dedup never silently overwrites/skips | Phase 0 (hash utility, partial) | Phase 3 (full UX) | Yes | None |
| I6 — Grouped results always a range, never mean/median | Phase 4 | Phase 4 | Yes, by schema/contract test | None |
| I7 — Grouping schemes are crop-only | Phase 4 | Phase 4 | Yes | None |
| I8 — Ties always recorded, never silently resolved | Phase 4 | Phase 4 | Yes | None |
| I9 — Peak is calculated, never hard-coded | Phase 0 (synthetic case, partial) | Phase 0 + Phase 3 (real use) | Yes | None — this is the strongest-tested invariant in the set (both a general unit test and a real-use integration test) |
| I10 — Re-running unchanged evaluation reproduces identical results | Phase 3 | Phase 3 | Yes | None |
| I11 — Migration reproduces `scenario_inputs`/`scenario_summary` exactly | Phase 2 | Phase 2 | N/A (one-time) | See §5 — the stated check is necessary but not sufficient; needs the additions listed there |
| I12 — Definitions always recompute live | Phase 5, 6a, 6b | Phase 5, 6a, 6b | Yes | None |
| I13 — Exports are frozen snapshots | Phase 5, 6a, 6b | Phase 5, 6a, 6b | Yes | None |
| I14 — No file written as a side effect of viewing | Phase 5, 6a, 6b | Phase 5, 6a, 6b | Yes | None |
| I15 — Failed validation never replaces a saved valid file | Phase 1 (inputs) | Phase 1; generalized (unstated) to Phase 5/6a/6b for definitions | Yes, but see §2 wording note | Minor: I15's literal text doesn't cover table/figure definitions; the phases apply it there anyway. Recommend clarifying the invariant's scope. |
| I16 — Engine semantics never changed without separate approval | Standing, from Phase 0 onward | Every phase (existing test suite must pass unmodified; diff review) | Yes, continuously | None — correctly treated as a standing check, not tied to one phase |
| I17 — Every persisted artifact carries sufficient provenance | Phase 3 (runs) *should be*, but proposal only lists Phase 5/6a/6b | **Gap**: not listed in Phase 3's gate at all | Would be, if added | **Add I17 to Phase 3's gate.** `run_manifest.csv` (Phase 3 ticket 6) is exactly the artifact I17 governs for runs; leaving it untested until Phase 5 means a run could exist for two phases with incomplete provenance before anyone checks. |

A phase should not be considered complete merely because its feature
works manually if a relevant invariant is untested — on that standard,
every phase in the proposal passes **except Phase 3**, which needs I17
added to its explicit gate.

---

## 5. Migration-equivalence gate

The proposal's existing gate (`migration_plan.md` §4: recompute
`scenario_inputs`/`scenario_summary` from the migrated evaluation via the
unchanged engine, compare exactly against current canonical outputs) is
necessary but not sufficient. Recommended minimum criteria, all of which
should block Phase 3 from starting if any fails:

1. **Exact match, `scenario_inputs`** — every row and column, against
   the current canonical output (existing gate, retained).
2. **Exact match, `scenario_summary`** — every row and column (existing
   gate, retained). This transitively exercises receptor/effects-metric/
   fate resolution, since those feed the closed-form grid — a pass here
   is strong evidence those layers migrated correctly too, not just
   agronomy.
3. **Explicit row-count assertions, not just row-by-row comparison.**
   Hard-code the expected row counts (e.g. 85 crops, 157
   `scenario_definitions` rows exploding to some known
   `use_patterns.csv` row count) into the migration test itself, as a
   second, independent check that doesn't rely solely on "the comparison
   happened to match." (This project's own AUD-099 finding — an
   acceptance criterion that compared against a stored value instead of
   an independent recomputation — is a direct precedent for why a
   redundant, hard-coded expectation matters here.)
4. **Reference/provenance file completeness**: `source_manifest.csv`,
   `review_core_assumptions.csv`, `review_effects_metrics.csv`,
   `table162_considerations.csv`, `table162_decision_matrix.csv`,
   `copied_register_manifest.csv` all present, byte-identical (SHA-256
   match), under the migrated evaluation's `inputs/reference/`. Not
   currently in the migration plan's stated inputs (§2 above) — must be
   added.
5. **Lossless named-set copy check** (already specified in
   `migration_plan.md` §5, retained): every value in each
   `data/reference/<file>.csv` appears unchanged in the corresponding
   migrated set file.
6. **Crop-grouping data carried forward**: if Table 162 support's
   crop-family mapping is in scope for migration (pending §6's decision),
   `STBAM_WORKBOOK_TO_CROP_FAMILY`'s 6 workbook→family mappings must
   appear, unchanged, in an initial `reporting_sets/` scheme. If it is
   explicitly declared out of scope instead, that decision must be
   recorded, not silently omitted.
7. **No truncation regression**: assert the migrated evaluation's first
   run produces the full crop count per workbook (e.g. 11 crops for
   `small_cereals`), not a subset — this is the direct, positive-control
   check that migration does not reintroduce the existing R7
   crop-dropdown truncation defect (`current_implementation_inventory.md`
   §15) into the new architecture's raw layer.
8. **Existing test suite passes unmodified** (`tests/testthat/`) — before
   and after the migration script is added to the repository, confirming
   I16 (engine untouched) throughout Phase 2's work.
9. **Re-runnability**: run the migration script twice against the same
   repository state; assert the second run's output is either rejected
   as a duplicate (per the dedup mechanism, once it exists) or byte-
   identical to the first — this is `migration_plan.md`'s own stated
   "re-runnable and testable" requirement (ADR-015), made concrete.

Any single failure among 1–9 should block migration from being
considered complete — consistent with the existing plan's own instruction
that a mismatch "must be resolved (not worked around) before proceeding."

---

## 6. Cross-cutting decision checkpoints

### A. Old override-based Shiny app

The proposal's recommendation (decide after Phase 2, once "the new app
has a working input-editing surface to compare against") is reasonable
but conflates two different decisions that should be separated:

- **When to start steering users toward the new app** — reasonable at
  the end of Phase 2, since that is the first point a real, migrated
  evaluation with actual scientific content exists in the new
  architecture, not just a hand-built test fixture.
- **When to formally retire/remove the old app's code** — should wait
  until **after Phase 7's full acceptance walkthrough passes**, not
  Phase 2. The old app is the only working, fully-featured surface for
  Runs/Results/Tables/Figures exploration until Phases 3–6 land; removing
  it after Phase 2 would leave users without a working results-viewing
  tool for several phases. Recommend keeping the old app fully
  functional and untouched (read-only reference, no new development)
  through Phase 6, with removal considered only once Phase 7's
  walkthrough demonstrates full parity — informed by whichever way §6.B
  and the Table162/Sensitivity decision below land, since the old app
  may need to keep serving those specific tabs even after the new app is
  otherwise feature-complete.

**New, higher-priority sub-decision this review surfaces**: the current
app's "Table 162 support" and "Sensitivity" tabs have no destination in
any planning document. Before the override-app retirement decision can
be made at all, the user needs to decide one of:
1. Port both into the new architecture (as their own explicitly-scoped
   phase, likely after Phase 5/6, since Table 162 support depends on
   `scenario_summary` + a reporting-group-like join, and Sensitivity is
   presently independent of runs entirely — sweeps a parameter live);
2. Declare both permanently out of scope for the redesign, with the old
   app (or a minimal standalone script) retained indefinitely as their
   only home; or
3. Declare them out of scope *for now*, explicitly deferred, revisited
   after Phase 7.
Any of the three is defensible; leaving it undecided is not — it
currently means "old app retirement" has no answerable stopping
condition.

### B. Old static figure batch

The proposal's recommendation (decide once Phase 6a demonstrates the new
mechanism covers the batch's primary use cases, i.e., after Phase 6a, not
before) is sound and is endorsed without change. One addition: whatever
the decision, recommend **archive, not delete** — the existing
581-file/~200MB batch is the only artifact set in this project's history
that received a fully independent SHA-256/existence/visual check
(`PROJECT_STATE.md`), and remains a useful before/after reference for
Phase 6a's own review, even after it is superseded.

---

## 7. Recommended final implementation sequence

The 8-phase (0–7, 6a/6b) skeleton is retained. Recommended modifications,
none of which change phase ordering or merge/split any phase boundary
beyond the two already-proposed 6a/6b split:

1. **Phase 2 gains one ticket**: a minimal evaluation-inputs → engine-
   parameter-set loader, reused unchanged by Phase 3's run lifecycle.
   This closes the dependency gap in §3's Phase 2 row.
2. **Phase 2's migration script scope expands** to cover: the 6
   provenance-only reference files, and (pending the Table162/Sensitivity
   decision, §6.A) extraction of `STBAM_WORKBOOK_TO_CROP_FAMILY` into an
   initial `reporting_sets/` scheme.
3. **Phase 2's gate expands** to the 9-point migration-equivalence
   checklist in §5, not just the original 2-point recompute-and-compare.
4. **Phase 1's ticket ordering is constrained**: build and get reviewed
   one full assumption category (recommend `seeding_sets`) before
   building the remaining four, rather than developing all five
   categories in parallel or batch. Does not change Phase 1's overall
   gate.
5. **Phase 3's gate gains I17** (run-manifest provenance completeness),
   and its ticket ordering is constrained similarly to Phase 1: hash +
   dedup + raw-result write + minimal manifest first, then
   `key_day_results`/on-demand generation/UI polish.
6. **A Table162/Sensitivity decision (§6.A) is made before Phase 2
   starts** — it changes Phase 2's scope (whether the crop-family mapping
   needs migrating) and determines whether a new phase needs to be added
   to the sequence at all (after Phase 5 or Phase 6, if porting is
   chosen).
7. **Phase 6a/6b's "parallel with Phase 5" note is made explicit** about
   requiring worktree isolation, consistent with the project's stated
   AI-workflow model.
8. **Phase 7's gate is narrowed** to require only Phase 6a's capabilities
   as a hard blocker, with 6b as enhancement, per §3's cross-phase note.

No phase is merged, dropped, or reordered relative to the original
proposal — every change above is additive (new ticket, expanded gate,
internal sequencing within an existing phase) or a scope clarification,
consistent with the review brief's instruction to change the proposal
only for concrete dependency/testing/risk reasons.

---

## 8. Suggested first implementation ticket

**Phase 0, ticket 1: the peak-finder utility.**

Rationale for starting here rather than with folder/schema work (Phase
1), even though Phase 1 is "larger": this is the smallest possible unit
of work that (a) is genuinely engine-adjacent (reads calculation output,
must not alter `R/calculations/*.R` or any validated numeric behaviour),
(b) has a crisp, already-specified acceptance test (I9: pass against the
current monotonic model *and* a synthetic non-monotonic case, proving the
mechanism is general rather than coincidentally correct for today's
model), and (c) is the natural first exercise of the independent-review
discipline this whole project already has a track record with
(`docs/independent_engine_audit.md`,
`docs/max_obtainable_exposure_review.md`) — proving that workflow works
smoothly on the very first ticket, before dozens of GUI tickets are
built on the assumption that it does. This is a description only, per
the review brief's instruction — it is not implemented in this session.

---

## 9. Human approvals required

**Before Phase 0 starts:**
- Approve this readiness review's recommended amendments (§7), or
  redirect them.
- Decide the Table162/Sensitivity fate (§6.A) — affects Phase 2's scope
  directly and may add a new, explicitly-scoped phase to the sequence.
- Confirm the migration-equivalence gate expansion (§5) as the
  authoritative acceptance criteria for Phase 2.
- Decide whether independent review gates apply to every phase or only
  the higher-risk ones — `implementation_phases_proposal.md` §9 already
  asks this and it remains unanswered; this review's own recommendation
  (§8) treats Phase 0's peak-finder as the first candidate regardless of
  the answer, since it is cheap enough to review unconditionally.

**At later gates (not blocking Phase 0, but should be decided when
reached, not silently assumed):**
- Q002 (`data/reference/` multi-set support) — confirmed non-blocking,
  revisit at/after Phase 1.
- Q003 (custom-day retroactive persistence) — confirmed non-blocking, the
  conservative "on-demand, unpersisted" default is sound; revisit only if
  a concrete need for retroactive persistence emerges.
- Old override-app's two-stage retirement decision (§6.A) — informal
  steer after Phase 2, formal removal only after Phase 7.
- Old static figure batch's archive decision (§6.B) — after Phase 6a.
- Exact evaluation-name/default-set-naming convention for migration
  (`migration_plan.md` §7) — implementation-time choice, non-blocking.

---

*End of review. No file other than this one was created or modified.*
