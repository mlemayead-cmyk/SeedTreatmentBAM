# Implementation dependencies and risks

**Purpose:** identify what must exist before what, and what could go
wrong, before proposing a phased implementation order
(`implementation_phases_proposal.md`).

---

## 1. Dependency graph

```text
[Folder + input schema]                (ADR-002/003/004/005/006)
        |
        +--> [Migration script]                       (ADR-015)
        |         (needs a working evaluation folder/input schema to
        |          write into and validate against; also needs the
        |          evaluation-inputs -> engine-parameter-set adapter
        |          below to run its own equivalence verification)
        |
        +--> [Evaluation-inputs -> engine-parameter-set adapter]  (new,
        |     added this session; migration_plan.md §3 step 4 — built in
        |     Phase 2 because migration's own verification gate needs it,
        |     reused unchanged by run lifecycle below, not rebuilt there)
        |
        +--> [Save/validation mechanics]               (ADR-006/007)
        |
        v
[Run lifecycle]                                        (ADR-008)
  (needs: input schema to snapshot; the adapter above, reused unchanged,
   to feed a snapshot into the *unchanged* calculation engine)
        |
        v
[Raw result persistence: scenario_inputs/summary/key_day_results]  (ADR-009)
  (needs: run lifecycle to have somewhere to write into; a peak-finder
   utility; the unchanged calculation engine)
        |
        v
[Reporting-group schema]  (ADR-010) -----+
        |                                 |
        v                                 v
[Grouped-result computation: grouped_results, grouped_result_bounds]  (ADR-011)
  (needs: raw results + a reporting-group scheme to group against)
        |
        +-------------------+
        v                   v
[Table architecture]   [Figure architecture]           (ADR-012, ADR-013)
  (needs: grouped +      (needs: grouped + raw results;
   raw results;           table architecture's definition/
   definition/export       export pattern as a template;
   pattern)                 additionally needs the level-of-
                            detail x series model, which is
                            genuinely more complex than tables)
        |                   |
        +---------+---------+
                  v
        [Shiny information architecture]                (ADR-014)
          (the picker screen can be built early and independently;
           full workspace screens depend on inputs, runs, results,
           tables, and figures all being implementable underneath)
```

**Key structural fact**: the *calculation engine itself*
(`R/calculations/*.R`) is a dependency of the raw-result layer but is not
modified by any of this work (I16, `invariants_and_test_plan.md`) — every
phase above builds an architecture *around* an unchanged engine, not a
replacement for it.

## 2. What can proceed in parallel vs. what is strictly sequential

- **Strictly sequential**: folder/input schema before migration; migration
  before there is a real evaluation to run; run lifecycle before raw
  results; raw results before grouped results; grouped results before
  tables and figures (both).
- **Can proceed in parallel once their shared dependency is ready**:
  - Table architecture and figure architecture, once grouped+raw results
    exist (figures are larger in scope, per the dependency graph note
    above, and likely take longer even if started at the same time).
  - The evaluation-picker screen (ADR-014) can be built as soon as the
    folder schema exists, ahead of the full workspace screens.
  - The peak-finder utility (needed by raw results) and the content-hash
    utility (needed by run lifecycle) are independent small pieces of
    shared infrastructure and can be built in either order, or together.

## 3. Risks

| Risk | Where it bites | Mitigation |
|---|---|---|
| **Content-hash non-determinism** — floating-point representation, row ordering, or platform differences could make two logically-identical input states hash differently (false dedup negative) or, worse, two different states hash identically (false positive). | Run lifecycle (ADR-008) | Canonicalize before hashing (stable sort, fixed numeric formatting); test I5/I10 explicitly across repeated runs and, ideally, across platforms if the app is ever run on more than one OS. |
| **Peak-finder correctness on a model that is currently monotonic** — a bug that happens to still return day 0 for the current model could go unnoticed without a deliberately non-monotonic test case. | Raw results (ADR-009) | I9's synthetic non-monotonic test case is mandatory, not optional, specifically to catch this. |
| **Excel round-trip data-quality issues** — locale decimal separators, silent numeric reformatting, encoding of special characters (e.g. crop names) on export/import. | GUI editing (ADR-006) | Validate every import against the same schema used for GUI edits (`folder_and_input_schema.md` §4); include a round-trip test (export then re-import) as part of the table's test suite. |
| **`use_patterns.csv` migration edge cases** — the current `scenario_definitions.csv` may have crops/uses that don't cleanly generalize to the normalized schema (e.g. unusual planting-method combinations, special characters, duplicate rate levels). | Migration (ADR-015) | Verify the transformation against the *full* current dataset, not a sample; the migration plan's §4 verification (exact match against canonical outputs) is designed to catch this by construction. |
| **Key-day dataset volume underestimated** — even a small milestone-day set, multiplied across every scenario x receptor x metric x diet-fraction, could be larger than expected at full scale. | Raw results (ADR-009) | Compute the actual expected row count against the full current scenario set before finalizing storage format; if unexpectedly large, this is a concrete, testable fact to bring back for review — not an assumption to build past. |
| **Figure architecture is materially more complex than table architecture** (level-of-detail x series, drill-down, envelope semantics) and could be underestimated in scope/time if planned identically to tables. | Figure architecture (ADR-013) | Phased separately from tables (see `implementation_phases_proposal.md`); consider implementing the `grouped` detail level fully before `individual`/`raw`, since `grouped` is what most directly replaces the current batch-figure use case. |
| **Existing 200MB static figure batch and existing outputs remain on disk** — **Resolved this session**: archived, not deleted, once Phase 6a demonstrates the new mechanism covers the batch's primary use cases (ADR-020's sibling decision; see `implementation_phases_proposal.md`'s Phase 6a/6b section). | Cross-cutting | Decision timing (after Phase 6a) unchanged from the original proposal; only the archive-vs-delete choice was resolved this session. |
| **Old override-based Shiny app's fate** — **Resolved this session (ADR-020)**: no phase gate 0-7 authorizes retirement. Informal steer toward the new app after Phase 2; formal code retirement only after Phase 7's walkthrough *and* Table 162/Sensitivity each reach their own disposition (ADR-016, ADR-017). | Cross-cutting | Tracked in `implementation_phases_proposal.md` §"Deferred capabilities and legacy retirement." |
| **Table 162 support and Sensitivity absent from every planning document** — identified by `implementation_readiness_review.md`; **resolved this session (ADR-016, ADR-017)**: both explicitly deferred, not dropped; source data preserved through migration; legacy modules remain available; dedicated future redesign checkpoints created, no phase number assigned. | Cross-cutting | See `implementation_phases_proposal.md` §"Deferred capabilities and legacy retirement." |
| **Source-tier conflation** — original assessment source documents (tier 1, sibling project), extracted reference data (tier 2), reviewer/document-analysis registers (tier 3), and calculated R-model outputs (tier 4) could be conflated during migration or a future Table 162 redesign, e.g. treating a copied register as a complete restatement of its source document, or recording an unverified/incorrect source-workbook path. Concretely surfaced this session: an initially-supplied "small cereals" workbook path was actually the `small_cereals_msa` (`SCENARIO_SOURCE`) workbook, not the `PRIMARY_AUDITED_REFERENCE` one. | Migration (ADR-015), Table 162 redesign checkpoint (ADR-016) | ADR-018's four-tier model, kept explicit in every provenance record; all 6 workbook paths plus the Table 162 document were independently hash-verified this session (`migration_plan.md` §0.1) rather than trusted from a single unverified statement. |
| **Concurrent editing of one evaluation** (e.g. two browser tabs, or a future multi-user scenario) is not addressed by any ADR in this redesign. | Cross-cutting | Explicit non-goal for this phase of work; single-user, single-session use is assumed throughout, consistent with the current app's usage pattern. |

## 4. What this document deliberately does not do

- It does not assign time estimates — those depend on implementation-time
  decisions (which AI coding agent, what pace) outside this specification's
  scope.
- The cross-cutting risks previously left open here (old app's fate, old
  figure-batch's fate, Table 162/Sensitivity's disposition, source-tier
  provenance) are now resolved via ADR-016 through ADR-020
  (`assessment_workspace_architecture.md`) and reflected in the risk table
  above — this document is not the place further changes to those
  decisions would be recorded; the ADR log is.
