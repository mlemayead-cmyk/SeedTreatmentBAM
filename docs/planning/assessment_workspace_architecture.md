# Architecture decision record — assessment/workspace redesign

**Status of this document:** living record, updated incrementally as
decisions are made. Do not silently rewrite an `Accepted` entry — if new
evidence suggests revisiting one, bring it back to the user explicitly and
record the change as a new dated note under that entry, not a silent edit.

**Scope:** this redesign concerns persistence, data architecture, GUI,
workflow, reporting, aggregation, and output management for `stbam`. It does
**not** authorize changes to validated calculation semantics. Any decision
that would require changing calculation semantics is flagged inline as:

> **SCIENTIFIC MODEL CHANGE — HUMAN APPROVAL REQUIRED**

**Companion document:** `docs/planning/unresolved_questions.md` (question
register — architecture/UX/data/reporting/scientific/migration/validation
questions raised but not yet resolved, kept separate so scientific judgement
questions never get silently folded into software-design decisions).

**No production code, reference data, tests, or existing documentation has
been modified as part of this planning phase.** This document and its
companion are the only files created/edited during this phase, until the
user explicitly authorizes implementation.

---

## Why this redesign

The current architecture (`R/inputs/11_parameter_set.R`) is
baseline-plus-override: an immutable `stbam_baseline` read from
`data/reference/*.csv`, plus a per-session `stbam_parameter_set` whose
`overrides` tibble records only what changed. `export_scenario_config()`'s
own docstring states this explicitly: *"Exports only the override layer.
The baseline is reproducible from the source workbooks and is not
duplicated into scenario files."* This is architecturally sound for a
single, semi-permanent assessment with occasional what-if exploration, but
it does not match the desired product direction: complete, self-contained,
human-readable assessment workspaces that do not depend on session state or
on the concept of an "override" to be understood.

This redesign is about **where the complete, authoritative record of an
assessment's inputs lives**, and how results, reporting, and figures relate
to it — not about changing what the engine calculates.

---

## Decisions

### ADR-001 — Top-level unit: one assessment = one complete active-ingredient risk assessment

Status: Accepted

#### Context
Before designing the folder schema, GUI, or grouping model, we needed to
settle what one "assessment" workspace represents — is it a whole
active-ingredient risk assessment, a single crop/use, or a freely-scoped
container with no fixed mapping?

#### Decision
One assessment = one complete active-ingredient risk assessment (e.g.
"thiamethoxam_bam_2026"), containing many use patterns/crops as sub-records
inside it.

#### Alternatives considered
- **A (chosen)** — one AI's full risk assessment as the top-level unit.
- **B** — one crop/use pattern per assessment (rejected: multiplies
  workspace count substantially; conflicts with the "complete,
  self-contained" requirement since crop-family reporting groups would then
  need to span multiple assessment folders).
- **C** — freely-named container with no fixed mapping to AI or crop
  (rejected as the default: risks an undisciplined concept with no clear
  convention; complicates where reporting-group definitions live).

#### Rationale
Matches how the source Word assessment document and the six source
workbooks are already organized (one thiamethoxam assessment already spans
small cereals, canola, cucurbits, and both legume workbooks). Matches the
user's own illustrative folder sketch, where `inputs/uses/use_patterns.csv`
lives inside one assessment folder and crop grouping (§7 of the request) is
edited within an assessment, not across assessments.

#### Consequences
- The current thiamethoxam project becomes the first (and for now, only)
  assessment workspace under the new architecture (see Decision 15,
  migration, not yet reached).
- "Use pattern" (one crop × rate × planting method registration) becomes a
  first-class sub-record type within an assessment, not a top-level unit.
- Reporting/crop groups are scoped to one assessment; a group definition
  does not need to reference anything outside its own assessment folder.

#### Scientific implications
None. This is a persistence/organization decision only.

#### Open follow-ups
None yet.

---

### ADR-002 — Terminology and top-level folder structure: `evaluations/Evaluation_Name/{inputs/, outputs/}`

Status: Accepted

#### Context
Following ADR-001, we needed to decide the top-level folder subdivision
inside one workspace, and confirm the exact unit the Shiny GUI operates on.

#### Decision
**Terminology:** the workspace unit is called an **evaluation**, not an
"assessment" (avoids collision with "assessment" meaning the underlying
PMRA risk-assessment document/process itself). All subsequent decisions,
code, and documentation in this redesign use "evaluation." This document's
own filename is left as-is for now to avoid mid-session churn; a rename can
be revisited before implementation if desired.

**Structure:** exactly two top-level subfolders per evaluation:

```
evaluations/
    Evaluation_Name/
        inputs/     <- complete, authoritative, hand-editable assumptions
        outputs/    <- everything generated: raw results, grouped results,
                       tables, figures, reports, run/provenance information
```

The evaluation folder (`evaluations/Evaluation_Name/`) is the exact unit
the Shiny GUI creates, opens, edits, runs, and reloads.

#### Alternatives considered
- **A (chosen, refined)** — `inputs/` + `outputs/`, matching this
  project's existing `outputs/` convention.
- **B** — six top-level siblings (`inputs/`, `results/`, `tables/`,
  `figures/`, `reports/`, `provenance/`) as originally sketched (rejected:
  new convention relative to the app's existing generated-content
  organization; less clear "authoritative vs. regenerable" signal).
- **C** — organize primarily by run rather than by content type (deferred
  to Decision 8, run lifecycle).

#### Rationale
User-directed refinement of option A: nests both `inputs/` and `outputs/`
one level inside a named evaluation folder (rather than a bare project
root), so that the evaluation folder itself is the single, movable,
copyable, deletable unit — supporting clone/rename/delete operations
cleanly (§3 of the request) without touching anything outside that one
folder.

#### Consequences
- `outputs/` (and everything under it) must always be safely deletable and
  fully regenerable from `inputs/` + the recorded model/engine version —
  this becomes an architectural invariant to test later (ties to
  invariant list item 4 and the general "raw results never destroyed by
  aggregation" principle).
- Internal subdivision of `inputs/` (Decision 4) and of `outputs/`
  (raw/grouped/tables/figures/reports/provenance — later decisions) is
  deliberately deferred; only the top two levels are settled here.
- The existing `data/reference/`, `data/scenarios/`, `data/processed/`
  layout is superseded by this structure for evaluation-scoped content;
  how (or whether) `data/reference/` continues to serve as the *default*
  source is Decision 3, not yet reached.

#### Scientific implications
None.

#### Open follow-ups
- Exact subdivision of `inputs/` — Decision 4.
- Exact subdivision of `outputs/` (raw vs. grouped vs. tables vs. figures
  vs. reports vs. provenance) — later decisions (§6, §9, §10, §12 of the
  request).
- ~~Whether `evaluations/` lives inside the existing project root or
  elsewhere on disk~~ — resolved by ADR-003.

---

### ADR-003 — Default-assumption location: keep `data/reference/` as-is

Status: Accepted

#### Context
Following ADR-002, we needed to decide where the central "default"
scientific values live, and how a new evaluation's `inputs/` folder gets
its starting content.

#### Decision
`data/reference/*.csv` (13 files) remains the central default template, at
its current location and with its current names — no migration of this
directory. At evaluation creation, the GUI copies every file wholesale into
the new evaluation's `inputs/` folder as a complete, disconnected copy (not
a reference/symlink). `evaluations/` is added as a new sibling directory at
the project root, alongside the existing `data/`, `R/`, `docs/`, etc.

#### Alternatives considered
- **A (chosen)** — keep `data/reference/` as-is.
- **B** — relocate/rename to `defaults/` at the project root (rejected for
  now: no functional benefit over A beyond naming clarity, and avoids an
  unforced migration step; can be revisited before implementation if the
  "reference" name proves confusing once evaluations exist alongside it).
- **C** — no central defaults, clone-only (rejected: loses the ability to
  update central defaults once and have future evaluations pick them up,
  which the request's §4 explicitly wants).

#### Rationale
Minimal churn: `data/reference/` is already exactly the right content, at
the location `load_baseline()` already expects, requiring no path changes
to any existing loader.

#### Consequences
- `data/reference/` keeps its current name despite that name originating
  from the override-era architecture; worth a documentation note when
  `evaluations/` exists alongside it so a future reader isn't confused
  about which one is "the truth" (answer: `data/reference/` is the
  template; each evaluation's own `inputs/` is the truth for that
  evaluation).
- The exact copy-on-create mechanism, and the invariant that updating
  `data/reference/` must never retroactively alter an existing evaluation,
  becomes a concrete architectural invariant to test later.
- Q001 (from ADR-002's follow-ups) is resolved: `evaluations/` sits at the
  project root, `data/reference/` is unchanged.

#### Scientific implications
None.

#### Open follow-ups
- Exact copy mechanism (file-by-file copy vs. some other method) —
  implementation detail, not an architecture decision; deferred to the
  implementation-phase specification.

---

### ADR-004 — Input boundaries: named, multiple assumption SETS per category, not one fixed file per concept

Status: Accepted

#### Context
The initial framing of Decision 4 (subdivide `inputs/` by scientific
concept vs. keep it flat) undersold the real requirement. The user does not
want one file per concept (e.g. one `receptor_parameters.csv`); they want
each concept to support **zero, one, or several complete, independently
named alternative sets** — e.g. "2020 seeding assumptions," "2026 seeding
assumptions," "EAB seeding assumptions," "RUAS seeding assumptions" as
parallel, selectable candidates, not a version sequence. The same applies to
receptor definitions (generic vs. broader multi-species vs. one or more
focal-species sets), effects metrics, fate/dissipation parameters, and
(later, not yet) reporting definitions and use patterns.

#### Decision
1. **No fixed 1:1 mapping between a scientific concept and one file.** Each
   assumption category is a *folder of named sets*, any one of which can be
   selected for a given evaluation:

```text
Evaluation_Name/
  inputs/
    uses/
      use_patterns.csv          <- single table for now (see point 4)

    assumptions/
      agronomy/
        seeding_sets/
          <named complete seeding-assumption-set files>
      receptors/
        receptor_sets/
          <named complete receptor-set files — body weight, food intake,
           MSA/search-area, taxon/species identity together, not just
           body weight>
      effects/
        effects_sets/
          <named complete effects-metric-set files>
      fate/
        fate_sets/
          <named complete dissipation/fate-assumption-set files>
      reporting/
        reporting_sets/
          <named complete crop/reporting-group-definition files>

    reference/
      <read-only provenance/cross-reference material — source manifests,
       Table 162 registers, and similar; not meant for routine editing>

  outputs/
    ...
```

2. **Every set carries stable identity and metadata**: set ID, name,
   description, source, date/version (where relevant), status, notes. Not
   yet decided: the exact file format for this metadata (a header block in
   each set file, a companion manifest CSV per category, or both) —
   deferred to the input-file-format specification, not a blocking
   architecture question.
3. **No hard-coded `V1/V2/V3` sequential-version semantics.** Sets may be
   genuinely different scientific approaches or sources, not just
   chronological revisions of one lineage.
4. **`use_patterns.csv` stays a single complete table for now** (one row
   per crop/use/rate combination), not yet subdivided into sets — but the
   folder structure must not preclude adding `use_pattern_sets/` later
   without a major redesign.
5. **Whatever set is actually selected for a completed evaluation is
   copied in full into that evaluation's own `inputs/` folder** — an
   evaluation never merely references a set by ID against some external
   library; it contains the actual content, preserving the
   self-contained/reproducible requirement from the request's §4.
6. **Selected-set identity propagates into run/results metadata** —
   `seeding_set_id`, `receptor_set_id`, `effects_set_id`, `fate_set_id` (and
   later `use_pattern_set_id`, `reporting_set_id` if those become sets too)
   are recorded wherever run provenance is recorded (exact mechanism is
   part of Decision 8/9, not yet reached), enabling later cross-set
   comparison of results.
7. Editable scientific inputs (`assumptions/`, `uses/`) remain separated
   from read-only provenance (`reference/`), per the original option C.

**Explicitly deferred, not decided here:** how a user selects, creates,
edits, or compares assumption sets through the GUI. That belongs to
Decision 6 (GUI editing) and the run-lifecycle decisions (Decision 8/9).

#### Alternatives considered
- **C, extended (chosen)** — sets, not single files, within the
  editable/provenance split already agreed.
- **A** — full conceptual subfolders with provenance folded into the
  nearest assumptions/ subfolder (superseded — the set concept makes a
  clean provenance/assumptions split more important, not less).
- **B** — flat `inputs/*.csv` (superseded — cannot represent "several named
  alternative sets" without inventing an ad hoc naming convention in the
  filename itself, which is exactly what named-set folders avoid).

#### Rationale
Matches a real scientific workflow need articulated directly by the user:
comparing results under materially different, equally legitimate
assumption sets (e.g. different seeding-rate data sources), not merely
tracking revisions of one dataset. A version-only model (`V1/V2/V3`) would
misrepresent sets that are alternatives, not successors.

#### Consequences
- `data/reference/` (ADR-003), as currently structured, is **single-set
  per category** — it does not yet have a "multiple named default sets"
  concept. Whether the *central* template also needs to support multiple
  named candidate sets, or whether set variety only emerges once
  evaluations exist (via cloning/editing), is a new open question — logged
  as Q002.
- The reference-data extraction/audit trail already established for the
  current thiamethoxam data (SHA-256 provenance, `PRIMARY_AUDITED_REFERENCE`
  vs. `SCENARIO_SOURCE` roles) needs a place to live per set, not just per
  file — likely inside each set's own metadata (point 2 above), to be
  confirmed when the file-format specification is written.
- This increases the input-schema's structural complexity relative to
  today's flat CSV layout. Considered and accepted as necessary, given the
  explicit multi-set requirement.

#### Scientific implications
None directly — this is a data-organization decision. It does, however,
enable a scientific capability (comparing results across assumption sets)
that does not exist today; the sets' *content* remains subject to the same
"do not silently invent scientific values" discipline as the current
`data/reference/` files.

#### Open follow-ups
- Q002 (new) — does the central default template (`data/reference/`) need
  to support multiple named sets per category, or does set variety start
  only at the evaluation level?
- Exact per-set metadata file format — deferred to the file-format
  specification (§21 deliverable "Data/file schema"), not an architecture
  blocker.
- GUI mechanics for set selection/creation/editing/comparison — deferred to
  Decision 6 and the run-lifecycle decisions.

---

### ADR-005 — Use-pattern record model: single normalized `use_patterns.csv`, one row per atomic use condition

Status: Accepted

#### Context
`ADR-004` fixed `use_patterns.csv` as one table per evaluation. Decision 5
settled what one row represents and how multi-planting-method uses are
stored.

#### Decision
- **One `use_patterns.csv` per evaluation** — not one file per use.
  Efficient bulk data entry/review/QA-QC was the stated priority.
- **Long/tabular, normalized structure**: one row = one atomic modelled use
  condition. Columns include (at minimum) `use_id`, `crop`, treatment rate
  + unit, and `planting_method` — i.e. the same shape
  `scenario_definitions.csv` already effectively has, generalized with an
  explicit `use_id`.
- **A crop/rate use permitted under several planting methods becomes
  multiple rows sharing one `use_id`**, each differing only by
  `planting_method` — never a list packed into one cell.
- **The Shiny GUI may present this as one logical "use" with a
  multi-select for planting methods**, exploding to normalized rows
  internally on save; the file itself stays fully normalized regardless of
  how the GUI displays it.
- **Scope discipline**: `use_patterns.csv` holds label/proposed-use
  information only — crop/use identity, treatment rate + unit, permitted
  planting method(s), and optional registration/context metadata (e.g.
  product identifier, region, target pest). It does **not** hold
  quantitative seeding/agronomic assumptions (TKW, seeding rate bounds,
  surface-seed fraction) — those remain in the separately-selectable
  `agronomy/seeding_sets/` from ADR-004, joined by crop name at
  calculation time exactly as today.
- Schema left extensible for genuinely more complex label relationships
  later, without pre-building that complexity now.

#### Alternatives considered
- **Chosen** — single normalized file, long format.
- One-file-per-use (rejected: works against efficient bulk entry/QA-QC,
  the user's stated priority).
- Wide format with a planting-methods list column (rejected: normalized
  rows are simpler to validate, join, and query; GUI can still present a
  multi-select).
- Full registration-style record now (superseded — deferred as optional
  future extension rather than built immediately).

#### Rationale
Matches the current data's own shape almost exactly (today's
`scenario_definitions.csv` is already long/normalized by rate_level; this
generalizes that same pattern with an explicit `use_id` and a planting
method column), while directly supporting efficient bulk review.

#### Consequences
- `use_id` becomes the join key linking `use_patterns.csv` rows to
  calculation results and, eventually, to run metadata — needs to be
  stable and unique within one evaluation.
- The GUI's use-editing view (Decision 6) needs to reconcile the
  normalized-storage / grouped-display distinction explicitly — flagged
  for that decision, not solved here.
- Keeping agronomy assumptions out of `use_patterns.csv` is what makes the
  ADR-004 "swappable seeding sets" capability actually work: the same use
  pattern can be evaluated against different seeding sets without
  duplicating use data.

#### Scientific implications
None.

#### Open follow-ups
- Exact column list for `use_patterns.csv` (beyond the minimum stated
  above) — deferred to the file-format specification.
- How the GUI reconciles grouped multi-select entry with normalized
  storage — Decision 6.

---

### ADR-006 — GUI editing: CSV authoritative on disk, with validated Excel round-trip; grid + form/modal in Shiny

Status: Accepted

#### Context
Decision 6 was posed as a GUI-pattern question (grid vs. form vs. hybrid).
The user redirected it: the real requirement is dual support for
convenient structured editing *inside* Shiny **and** efficient bulk
entry/exchange through Excel, and asked for an investigated recommendation
on file format and mechanism rather than a forced pick among three
UI patterns.

#### Requirements (as stated by the user, recorded verbatim in substance)
1. The saved evaluation contains complete input datasets, not overrides or
   patches (already established, ADR-002/003).
2. Users can view/review the whole dataset in Shiny.
3. Structured GUI editing provides appropriate validation.
4. Bulk import from Excel (or another practical tabular format) is
   supported.
5. Imported data is validated before it is allowed to replace previously
   saved valid data.
6. The underlying files remain accessible and understandable outside
   Shiny.
7. Multiple named assumption sets (ADR-004) must be manageable under this
   same mechanism.

#### Investigation
- The project already uses `readr`/CSV as the authoritative format for
  every existing reference table, `DT` for in-app grid display everywhere,
  and `writexl` (already a required dependency) for XLSX *export*.
- **Verified live in this environment:** `readxl` (XLSX *import*) is
  already installed, even though it is not yet in the project's declared
  dependency list; `openxlsx` is not installed. Given this machine has no
  CRAN access, `readxl`'s prior availability removes what would otherwise
  have been a real practical risk to an Excel-import capability.
- CSV as the on-disk authoritative format is plain text: diffable in git
  (supports requirement 6 and general scientific traceability), free of
  Excel-specific corruption risks (silent numeric reformatting, locale
  decimal-separator differences, formula/macro surprises), and requires no
  format conversion for anything already in `data/reference/`.
- XLSX as the on-disk authoritative format would satisfy Excel-native
  editing slightly more directly, but is a binary format (opaque `git
  diff`, undermining traceability), is a larger departure from the
  project's existing convention (100% of current reference data is CSV),
  and gains nothing that a CSV-plus-round-trip design does not already
  provide.

#### Decision
- **CSV remains the authoritative on-disk format** for every input file in
  `inputs/` (uses, every named set, reference material) — no exception.
- **The Shiny GUI provides, per editable table:** a `DT` grid for
  viewing/bulk review (satisfies requirement 2); a validated add/edit
  form or modal for structured single-record changes (requirement 3,
  consistent with the "C, extended" direction from the original Decision
  6 framing); a "Download as Excel" export (`writexl`, already available)
  for external bulk editing; an "Upload Excel or CSV" import path
  (`readxl`, confirmed available, plus `readr` for CSV) that **validates
  the uploaded data against the table's schema (columns, types, permitted
  values/choices, referential integrity such as crop names matching a
  planting-method set) before it is allowed to replace the saved file**
  (requirement 5) — a failed validation never overwrites the previously
  saved, valid dataset.
- This single mechanism applies uniformly to every named-set category
  from ADR-004 (requirement 7), not a bespoke mechanism per category.

#### Alternatives considered
- XLSX as the authoritative on-disk format (rejected — see investigation:
  worse traceability, bigger departure from existing convention, no net
  capability gain over CSV-plus-round-trip).
- Grid-only or form-only editing (superseded by the user's broader
  requirement; both are simply components of the combined mechanism now,
  not competing choices).

#### Rationale
Directly satisfies all seven stated requirements without forcing a
false choice between "Shiny-native editing" and "Excel-based bulk entry" —
both are supported over the same authoritative CSV files, and the
validate-before-replace rule protects data integrity regardless of which
entry path was used.

#### Consequences
- `readxl` needs to be added to `scripts/check_environment.R`'s
  `REQUIRED` list before implementation (currently listed only as an
  unused-but-installed package; not yet a declared dependency). Already
  confirmed installed, so this is a documentation/declaration change, not
  an installation risk.
- A validation-schema definition is needed per input table (columns,
  types, permitted values, referential-integrity rules) — this becomes
  part of the file-format specification (§21 deliverable), and is also the
  natural place to encode "add a row where scientifically permissible /
  delete a row where permissible" rules from the original request §11.
- The exact grid/form component choices (e.g. `DT`'s editable-cell mode
  vs. a separate modal) are implementation detail, not settled here.

#### Scientific implications
None directly. The validation layer this decision requires *is* where
scientific guardrails (e.g. rejecting an out-of-range body weight) will
live — its rules matter scientifically even though the file-format choice
itself does not.

#### Open follow-ups
- Per-table validation schema definitions — file-format specification.
- Exact grid/form/modal component design — implementation phase.
- Add `readxl` to the declared dependency list — implementation phase.

---

### ADR-007 — Save behaviour: both per-table explicit save AND a whole-evaluation save-all action

Status: Accepted

#### Context
Decision 7 asked when GUI edits are written to disk: immediately, per
table on an explicit action, or as one whole-evaluation transaction. The
user chose to keep both the per-table and whole-evaluation mechanisms
rather than pick one.

#### Decision
Both save granularities coexist:
- **Per-table explicit save** — each editable table's grid/form view has
  its own "Save" action. Edits to that table are held as a clearly-marked
  in-session draft until saved; validation runs at save time; only a valid
  table is written to disk.
- **Whole-evaluation save-all action** — a single "Save evaluation" (or
  equivalent) action validates and commits every currently-dirty table
  across the evaluation together, all-or-nothing: if any dirty table fails
  validation, none of them are written.
- Live/immediate save (option A) is not used — every write path goes
  through validation first, whether triggered per-table or evaluation-wide.

#### Alternatives considered
- B only (per-table) — superseded, user wants the convenience of a bulk
  commit too.
- C only (whole-evaluation only) — superseded, user wants the granularity
  of saving one table without needing every other open table to also be
  valid at that moment.
- A (immediate/live save) — rejected, no deliberate review point before
  writing to disk.

#### Rationale
Neither granularity alone covers both workflows the user wants: careful,
incremental single-table edits, and convenient "I touched several things,
commit them all now" bulk saves. Supporting both is a straightforward
superset, not a conflicting design.

#### Consequences
- The GUI needs to track per-table "dirty" state regardless of which save
  path is used, so both the per-table Save button and the evaluation-wide
  Save-all button can reflect accurate state (e.g. greying out Save-all
  when nothing is dirty).
- Validation logic must be callable both per-table (one schema check) and
  in aggregate (run every dirty table's schema check before committing
  any of them) — a single validation function per table, invoked in a
  loop for the whole-evaluation case, is the natural implementation shape
  (not decided here, just noted for the implementation phase).
- Needs a clear UI signal distinguishing "unsaved draft," "saved," and (a
  later concern, Decision 8) "saved but not yet reflected in the most
  recent run's results."

#### Scientific implications
None.

#### Open follow-ups
- Exact UI treatment of dirty/saved/stale-run state — implementation
  phase, informed by Decision 8 (run lifecycle).

---

### ADR-008 — Run lifecycle: every scientifically distinct run preserved automatically; presentation artifacts generated on demand from a chosen run

Status: Accepted

#### Context
Decision 8 asked whether runs are preserved automatically or overwritten
by default. The user confirmed automatic preservation (option A) with two
important qualifications that substantially shape the design: (1) a
preserved *run* must not be conflated with automatically generating every
possible presentation artifact, and (2) an old run's reproducibility must
survive later edits to the named assumption sets it used.

#### Decision

**Conceptual model** (stated by the user, adopted as the governing
mental model for everything downstream):

> Evaluation = the ongoing working assessment.
> Input sets = editable scientific information.
> Run = a frozen calculation using a particular combination of those
> inputs.
> Figures/tables/reports = presentation products generated from a chosen
> run.

**A preserved run contains or reproducibly retains:**
1. The exact complete input state used — an **immutable snapshot of actual
   input values**, not merely references/IDs to assumption sets. This is
   the critical point: if `receptor_sets/generic.csv` is edited six months
   later, an old run recorded only as `receptor_set_id = generic` would no
   longer be reproducible. Because these input tables are relatively
   small, the run keeps its own frozen copy of the actual content used.
2. The selected use patterns (from `use_patterns.csv` at run time).
3. The IDs/names of every assumption set used (seeding, receptor, effects,
   fate, and others as they are added) — kept *alongside* the immutable
   value snapshot (point 1), not instead of it, so a run is both
   human-identifiable ("this used the EAB seeding set") and reproducible
   even after that named set changes later.
4. Raw/canonical calculation results.
5. Grouped/aggregated results.
6. Validation status.
7. Model version / git commit and other reproducibility provenance.
8. A run ID, date/time, and an optional user-supplied description/name
   (e.g. "2026 seeding + generic receptors," "EAB seeding + focal
   species") so multiple runs remain distinguishable and comparable at a
   glance.

**A preserved run does NOT automatically contain:** hundreds of PNG/SVG
figures, Word tables, or reports. Those presentation outputs are generated
**on demand**, from a chosen run, only when requested — not bundled into
every run automatically. This directly addresses the volume problem
already identified separately (the current static batch script's ~288
logical figures × 2 formats) by construction, without yet deciding the
figure architecture itself (a later decision, §9 of the request).

**Illustrative structure** (not prescribed exactly; implementation may
refine it):

```text
Evaluation/
  inputs/
    ...
  outputs/
    runs/
      Run_001/
        inputs_snapshot/    <- frozen copy of every input file actually used
        raw_results/
        grouped_results/
        run_manifest        <- IDs, provenance, validation status, description
      Run_002/
        ...
    figures/                <- generated on demand, references a run
    tables/
    reports/
```

**Deduplication (investigated, recommended, not fully specified):** the
user asked whether repeated "Run" clicks with no scientifically meaningful
input change should be reliably detected to avoid redundant identical
preserved runs. **Recommendation:** compute a deterministic content hash
(e.g. SHA-256) over the canonicalized, concatenated content of everything
that would go into `inputs_snapshot/` for that run. Before creating a new
run, compare this hash against existing runs' stored hashes (in their
`run_manifest`s):
- **On a match:** do not silently reuse or silently skip. Tell the user
  explicitly that this exact input configuration matches an existing run
  (naming it), and let them either treat that existing run as current or
  explicitly force a new run anyway (e.g. to test reproducibility). Never
  silently overwrite, and never silently no-op without telling the user
  what happened — this was the user's explicit hard requirement.
- **On no match:** proceed to create a new run normally.

This satisfies "a distinct scientific configuration must never be silently
overwritten" while avoiding unbounded accumulation of genuinely identical
runs, without prescribing the exact hashing/canonicalization mechanics,
which are implementation detail.

#### Alternatives considered
- Overwrite-in-place with opt-in snapshot (Decision 8's original option
  B) — superseded, does not meet the "must not rely on the user
  remembering" requirement.
- Bundling full figure/table/report generation into every run
  automatically — explicitly rejected by the user as conflating "run" with
  "presentation," and as the direct cause of the current batch script's
  figure-volume problem.
- Reference-only assumption-set recording (`receptor_set_id = generic`
  with no value snapshot) — explicitly rejected: does not survive later
  editing of the named set, breaking reproducibility.

#### Rationale
Separates three genuinely distinct concerns — editable inputs, frozen
calculations, and on-demand presentation — that the current architecture
does not distinguish at all (today there is no persisted "run" concept of
any kind). This is also what makes the cross-assumption-set comparison
capability from ADR-004 actually reproducible over time, not just
possible at the moment of comparison.

#### Consequences
- `inputs_snapshot/` duplicates input-table content across runs by
  design (accepted trade-off — these tables are described as
  "relatively small," so the storage cost is judged acceptable against
  the reproducibility guarantee it buys).
- The GUI needs a "which run is this evaluation's results view showing"
  concept everywhere results are displayed — ties into Decision 9 (raw
  result persistence) and the still-open figure architecture (§9 of the
  request, not yet reached).
- A content-hashing utility becomes a shared piece of infrastructure,
  needed both for dedup detection here and potentially for other
  reproducibility checks (e.g. confirming a re-run of an unchanged
  evaluation reproduces the same canonical results — architectural
  invariant 11 from the original request).

#### Scientific implications
None directly — this is a reproducibility/persistence architecture. It
does materially strengthen scientific defensibility (an old run can never
be silently invalidated by a later edit to a shared assumption set).

#### Open follow-ups
- Exact deduplication/hashing mechanics — implementation phase
  (recommendation given above, not fully specified).
- Exact run-naming/description UI — implementation phase.
- Exact figure/table/report on-demand generation mechanics — Decision 13
  (figure architecture), not yet reached.
- Whether/how `figures/`, `tables/`, `reports/` under `outputs/` record
  which run produced them — likely via a reference to the source run's ID
  in each artifact's own metadata/footnote (consistent with the existing
  `build_figure_metadata()`/`format_figure_footnotes()` pattern already in
  the codebase) — to be confirmed in Decision 13.

---

### ADR-009 — Raw persistence: complete scenario-level datasets + an automatic compact key-day dataset; full daily time course always on demand, never a "representative slice"

Status: Accepted

#### Context
Decision 9 asked which canonical datasets a preserved run stores in full
by default, given that a full `daily_timecourse` cross-product is already
documented in this codebase as impractically large ("on the order of a
gigabyte... useless as an artefact"). The user rejected all three
originally-framed options in favour of a more precise hybrid design.

#### Decision

**Persisted automatically, in full, with every run:**
1. Complete `scenario_inputs` (already closed-form, always covers every
   scenario).
2. Complete `scenario_summary` (already closed-form, always covers every
   scenario × receptor × metric × diet fraction).
3. A new **compact key-day time-course dataset**, covering **every
   applicable scenario** (not a sampled subset of scenarios), but only at
   a defined, small set of milestone days:
   - `peak` (see below — calculated, not assumed),
   - day 1, 2, 5, 10, 30 as a standard starting set,
   - additional standard days may be added if useful,
   - the user may request custom days be included in this automatically-
     persisted set for a given run.

**Generated on demand, not persisted by default, always exactly
reproducible from the run's frozen `inputs_snapshot` + recorded model
version:**
- A full daily time course over a user-selected interval, for
  user-selected scenarios/receptors/metrics/reporting groups.
- Ad hoc custom-day queries beyond whatever was included in the
  automatically-persisted key-day dataset for that run.

**Explicitly rejected concept: the "representative slice."** The current
architecture's notion of covering only a sampled *subset of scenarios* at
full daily resolution is replaced entirely by this design's opposite
approach: cover *every* scenario, but only at deliberately chosen,
named/meaningful *days*. Arbitrary scenario sampling is not carried into
the new architecture in any form.

**Peak must be calculated, not hard-coded.** The current engine
(`R/summaries/23_scenario_summary.R`) sets `peak_rq_day <- 0`
unconditionally, with a comment noting this is valid *because* the current
model's dose declines monotonically from sowing. The user requires the new
architecture to treat "peak" as a genuinely calculated result (found by
evaluation/search, not assumed to be day 0), so that a future model
version with different (e.g. non-monotonic) time-dependent behaviour would
not silently inherit an incorrect hard-coded assumption. For the *current*
model, a correctly-implemented peak search is expected to still find day 0
in every case (monotonic decline has already been independently verified —
`docs/independent_engine_audit.md`), so this is a robustness/generality
change to *how peak is computed*, not a change to any scientific
conclusion. **Not flagged as a scientific model change** — the underlying
equations and their monotonic behaviour are unchanged; only the computation
method that reports "which day is the peak" becomes general rather than
assumed. Exact search mechanics (e.g. evaluating a moderately fine day
grid and taking the argmax, vs. a closed-form solution if one exists for a
given model version) are implementation detail, not decided here.

#### Alternatives considered
- A (full scenario-level datasets + a representative *scenario* slice of
  daily_timecourse) — superseded; the user explicitly wants the "slice"
  concept removed in favour of full scenario coverage at fewer days.
- B (all four datasets in full, every run) — superseded, still has the
  same unbounded-growth problem the representative-slice design was
  originally introduced to avoid.
- C (only `scenario_summary` persisted) — superseded, `scenario_inputs`
  is confirmed wanted in full too.

#### Rationale
Inverts which dimension gets "sampled": today's design samples scenarios
(arbitrarily, by row order — the same defect family as the R7 crop-dropdown
finding in `docs/current_implementation_inventory.md`) and keeps every
day; the new design keeps every scenario and samples days, but
*deliberately* (named milestones plus explicit user choice), never
arbitrarily. This also directly serves the cross-scenario, cross-
assumption-set, cross-reporting-group comparison capability already
committed to in ADR-004/ADR-008 — a compact key-day dataset covering every
scenario is exactly what that kind of comparison needs, without requiring
a full daily expansion to get it.

#### Consequences
- The key-day dataset's exact column shape needs to record, per row, which
  named milestone (or custom day) it represents, so downstream comparison
  and grouping logic (Decision 10/11) can rely on it consistently across
  runs and reporting groups.
- A "peak-finding" utility becomes shared infrastructure, analogous to the
  content-hashing utility identified in ADR-008 — used at minimum inside
  the key-day dataset builder.
- On-demand full daily time course generation needs a clear, bounded
  scoping mechanism (selected scenarios/receptors/metrics/groups + day
  range) so a user cannot accidentally trigger the same gigabyte-scale
  computation the representative-slice design was built to avoid — this
  becomes part of the GUI/figure-architecture design (Decision 13).

#### Scientific implications
None — see the "peak must be calculated" note above for why this is
judged a robustness/generality change, not a scientific one, for the
currently-validated model.

#### Open follow-ups
- Exact key-day dataset schema (columns, milestone-day identification) —
  file/data-schema specification.
- Exact peak-search mechanics — implementation phase.
- Exact on-demand full-time-course request/scoping UI — Decision 13
  (figure architecture), not yet reached.
- Whether custom-day requests get *added to* a run's persisted key-day
  dataset retroactively, or are always a separate on-demand query — leaning
  toward "added to the persisted set only if requested at run time,
  otherwise on-demand," per the user's framing, but not explicitly
  confirmed; logged as Q003.

---

### ADR-010 — Reporting groups are multiple named, editable **crop-only grouping schemes**; rate, planting method, receptor, and metric stay separate reporting dimensions, never folded into a scheme

Status: Accepted

#### Context
Decision 10 asked how crops get grouped for comparison/reporting, given
that today's only mechanism is `STBAM_WORKBOOK_TO_CROP_FAMILY`, a single
scheme hard-coded in `R/summaries/24_table162_support.R`. The user chose
option B (multiple named schemes, mirroring the assumption-set pattern
from ADR-004) but added a decisive scoping constraint on what a
"grouping scheme" is allowed to group.

#### Decision
A **reporting grouping scheme** has exactly one target entity: **crop**.
A scheme is an editable, named crop -> group-label mapping (e.g.
`scheme: crop_family` mapping `Barley/Oat/Rye/Wheat -> Small Cereals`).
An evaluation may hold multiple such schemes side by side (e.g.
`crop_family`, plus any other scientifically/regulatorily meaningful
crop classification), stored as editable data inside the evaluation, with
the active scheme selectable per table/figure in the GUI.

Explicitly **not** grouping entities, and never folded into a
crop-grouping scheme: application rate, planting method, receptor,
effects metric, or any other use/scenario dimension. These remain
independent reporting dimensions that can be filtered, grouped-by, or
faceted alongside a crop-grouping scheme, but are never merged into the
scheme's crop -> label mapping itself. The canonical composed query shape
is:

```
crop reporting group (from a chosen crop-grouping scheme)
  x application rate
  x planting method
  x receptor
  x effects metric
```

with a *range* (not a mean/median — consistent with the aggregation-
transparency principle from the original request) calculated across the
individual crops and any other explicitly selected dimensions within that
group.

Additional constraints:
- Individual crop identity is always retained in raw results; grouping is
  a presentation/aggregation layer on top, never a replacement.
- Grouped results must remain traceable back to the specific contributing
  crops/scenarios (a grouped output must be able to answer "which raw rows
  fed this range?").
- A scheme may leave some crops ungrouped, or place a single crop in its
  own singleton group — broad aggregation is not mandatory for every
  evaluation.

#### Alternatives considered
- Plain "B" as originally framed (multiple named schemes with no
  constraint on target entity) — superseded; the user identified that
  without a defined target entity, a scheme could improperly mix a
  crop-level classification with a scenario-level dimension like planting
  method, producing groups that silently average across a dimension that
  should instead stay explicit.
- A (single editable scheme) / C (ad hoc, unpersisted) — superseded per
  Decision 10's original framing.

#### Rationale
Planting method (and rate, receptor, metric) can vary *for the same crop*
within an evaluation's use patterns (the `use_patterns.csv` design from
ADR-005). Treating any of these as a groupable "crop attribute" would let
a grouping scheme silently collapse a dimension the user wants to keep
explicit and inspectable, contradicting the aggregation-transparency
principle already established for this redesign (explicit rules, no
unexplained averaging). Restricting grouping schemes to crop-only keeps
the semantics of "what does this group mean" unambiguous, while still
letting the other dimensions be composed freely at query/report time.

#### Consequences
- The grouped-result data model (raw -> grouped -> presentation layering,
  already committed to earlier in this redesign) needs a query/aggregation
  interface that composes a *chosen crop-grouping scheme* with a set of
  *chosen reporting dimensions* (rate, planting method, receptor, metric),
  rather than a single flat "group by" concept — this feeds directly into
  the aggregation/figure-architecture specification (Decision 13 area).
- Grouped output records need to retain or reference the contributing raw
  row keys (scenario/crop/rate/method/receptor/metric identifiers) to
  satisfy the traceability requirement.
- Grouping-scheme files need a schema that supports partial coverage
  (ungrouped crops) and singleton groups, not just an exhaustive many-to-
  one mapping.

#### Scientific implications
None directly — this is a presentation/aggregation-layer decision. It
does reinforce an existing scientific-integrity safeguard: aggregation
must never silently mix a use/scenario dimension (like planting method)
into a crop classification, which could otherwise mask meaningful
variation within a reported "group."

#### Open follow-ups
- Exact grouping-scheme file schema (crop, group_label, scheme name,
  optional ordering/display metadata) — data-schema specification.
- Exact grouped-result traceability mechanism (row-key list vs. a join-
  able ID) — architecture specification.

---

### ADR-011 — Grouped-result content: range + stable scenario-ID bound identity + contribution counts; ties recorded explicitly in a companion table, never silently dropped

Status: Accepted

#### Context
Decision 11 asked what a grouped reporting result contains beyond the
`[min, max]` range already settled in ADR-010. The user chose option B
(range + bound identity + counts) with several refinements: bound identity
must be a stable scenario/raw-result ID, not "crop name" alone (since the
same crop can appear in a group under many rate/method/receptor/metric/
assumption-set combinations); ties at a bound must be preserved, not
silently resolved to "the first one"; single-contributor groups are
acceptable with `min = max`; and the grouped layer must stay compact,
never embedding every contributing raw value.

#### Decision

**Primary grouped-result table** — one compact row per (grouping scheme,
group label, selected reporting-dimension combination — e.g. rate x
planting method x receptor x metric x assumption-set IDs, per ADR-010's
composed query shape). Each row carries:
- `min_value`, `max_value`.
- `min_scenario_id`, `max_scenario_id` — a **stable reference to the
  underlying raw scenario/result ID** (not crop name alone), consistent
  with ADR-005's `use_id`/`scenario_id` keys and ADR-008's run/raw-result
  identifiers. Human-readable fields (crop, rate, planting method, etc.)
  are looked up from that ID for display, not stored as the identity
  itself.
- `n_scenarios` — count of contributing raw scenarios.
- `n_crops` — count of distinct contributing crops.
- Additional counts (e.g. `n_use_patterns`, `n_assumption_sets`) **only
  where a specific reporting/traceability purpose is identified** — not
  added speculatively, per the user's explicit instruction.
- `min_tied` / `max_tied` — boolean flags, `TRUE` when more than one
  scenario shares the extreme value at that bound.

When a group has exactly one contributing scenario: `min_value =
max_value`, `min_scenario_id = max_scenario_id` (the same scenario),
`n_scenarios = n_crops = 1`, both tie flags `FALSE` — the compact row
form is unchanged, and the counts make clear this is not a true range.

**Tie handling — companion long table, not silent first-pick, not full
embedding.** `min_scenario_id`/`max_scenario_id` in the primary table hold
one canonical, deterministically-chosen representative (e.g. the
lowest-sorted scenario ID among ties) so the compact row always resolves
to a single displayable driver. Full tie membership is preserved in a
separate, small, normalized companion table —
`grouped_result_bounds`(group row key, `bound_type` [`min`/`max`],
`scenario_id`) — containing **one row per contributing scenario at a
bound**, not one row per contributing scenario in the whole group. For a
non-tied bound this table has exactly one row; for a tied bound it has
one row per tied scenario. This keeps the primary table compact (a UI can
render `Small Cereals: RQ 1.2-8.7` immediately, with a `+2 tied` indicator
driven by the tie flags) while making every tied scenario queryable
without re-embedding the group's full raw membership (which remains the
job of the raw layer + `n_scenarios`/`n_crops`, not this table).

This directly supports the Shiny interaction the user described: a
compact group range shown at a glance, immediate visibility of which
scenario(s) drive each bound (including ties), and drill-down to full
contributing-row detail on request via the raw layer.

#### Alternatives considered
- A (range only) — superseded, does not meet the "immediately understand
  what is driving the range" requirement.
- C (range + full embedded breakdown of every contributing value) —
  explicitly rejected by the user; re-embeds the raw layer into the
  grouped layer, contradicting the raw/grouped/presentation separation
  already adopted throughout this redesign.
- Silently picking "the first" tied scenario with no record of the tie —
  explicitly rejected; the user required ties be preserved or exposed,
  not hidden.

#### Rationale
A companion long table scoped to *only the scenarios actually at a bound*
(not the whole group) is the smallest addition that fully satisfies the
tie-preservation requirement without reopening the "don't embed raw data
in the grouped layer" boundary the user just reaffirmed. It also follows
the same normalized-long-table convention already adopted for
`use_patterns.csv` (ADR-005) rather than introducing a new list-in-cell
pattern.

#### Consequences
- The grouped-result builder needs deterministic, documented tie-breaking
  logic for choosing the single representative ID shown in the primary
  table (e.g. lowest scenario ID) — implementation detail, but must be
  documented so the choice is not perceived as arbitrary.
- `grouped_result_bounds` needs a stable foreign key back to its owning
  grouped-result row (group scheme, group label, and the full reporting-
  dimension combination) — same keying concern already flagged for the
  primary table in ADR-010's open follow-ups.
- The Shiny grouped-result view needs a small additional query (join to
  `grouped_result_bounds`) to render "+N tied" and list tied scenarios on
  demand — implementation detail for the figure/table architecture
  (Decision 12/13, not yet reached).

#### Scientific implications
None directly — this is a data-model decision. It does materially
strengthen scientific defensibility: a grouped range can never obscure a
genuine tie or misattribute a bound to "crop" alone when the true driver
is a specific rate/method/receptor/metric/assumption-set combination.

#### Open follow-ups
- Deterministic tie-breaking rule for the primary table's single
  representative ID — implementation phase.
- Exact grouped-result and `grouped_result_bounds` keying scheme — data/
  file schema specification, alongside ADR-010's equivalent follow-up.
- Which additional contribution counts (if any) have a "clear reporting/
  traceability purpose" beyond `n_scenarios`/`n_crops` — deferred until a
  concrete need is identified, not decided speculatively now.

---

### ADR-012 — Report tables: saved definitions recompute live from the run; a persisted file exists only after an explicit Export/Save-snapshot/Add-to-report action

Status: Accepted

#### Context
Decision 12 asked whether report/presentation tables are persisted data
artifacts or always regenerated. The user chose option C (save the
definition, not the data) and added an explicit distinction between (1)
a saved, reusable table *definition*, whose numbers are always recomputed
live from its source run when viewed in Shiny, and (2) an intentionally
*exported* table, which should be retained as a frozen snapshot because it
may become part of an assessment/regulatory record.

#### Decision

**Two distinct objects, not one:**

```text
Preserved run
     |
     +--> saved table definition (small, reusable, editable)
     |        |
     |        +--> live/recomputed Shiny table (never persisted itself)
     |
     +--> explicit Export / Save snapshot / Add to report
              |
              +--> frozen CSV / XLSX / Word file (persisted artifact)
```

1. **Saved table definition** — a small, named, editable specification,
   not a copy of results. At minimum it records: source `run_id`;
   reporting/grouping scheme (ADR-010) and selected dimensions (which are
   retained vs. aggregated — ADR-011's composed query shape); filters;
   receptor/effects-metric selection; columns to display; ordering/
   formatting options; and a title/description. Viewing a saved definition
   in Shiny always recomputes its values from the source run's raw/grouped
   results at that moment — there is never a second, independently-stored
   copy of the numbers that could drift from the run.
2. **No automatic persistence to `outputs/tables/` from ordinary Shiny
   viewing.** Opening, browsing, or reconfiguring a table in the GUI never
   by itself writes a file. A persisted table file is created only by a
   deliberate user action — Export, Save snapshot, or (later) Add to
   report.
3. **An exported/finalized table is a frozen snapshot**, not a live
   artifact — it does not update if the source run's data or the table
   definition later changes. It is retained precisely because it may
   become part of the formal assessment/review record (regulatory
   submission, report appendix), where "what was actually produced at the
   time" must be preservable independent of later edits.

**Provenance requirements:**
- A saved table **definition** must retain enough to be interpretable
  later even if the reporting code evolves: `run_id`, the grouping scheme/
  dimension/filter/column configuration, and the **reporting/table-
  builder code version** (not just the calculation-engine's
  `STBAM_MODEL_VERSION` from ADR-008/ADR-009 — a table's *presentation*
  logic, e.g. how it composes and formats grouped results, can change
  independently of the underlying calculation engine). Recording both
  versions separately means a future reader can tell whether an old
  definition might render differently today because the science changed,
  the reporting/table logic changed, or neither.
- An **exported snapshot** must retain or be accompanied by: evaluation
  identity, source `run_id`, the table definition/configuration that
  produced it (or a reference to the saved definition, if one exists),
  generation date/time, and both the model version and reporting/table-
  builder version in effect at export time — mirroring the figure-
  provenance pattern already established in the current codebase
  (`build_figure_metadata()`/`format_figure_footnotes()`).

#### Alternatives considered
- A (always regenerate, nothing ever persisted) — superseded; does not
  meet the requirement that a reviewer-finalized table become part of a
  retained record.
- B (save the generated data itself as the reusable artifact) —
  superseded as the *default* mechanism (creates a second numerical
  source that can silently diverge from the run), but its essential
  capability survives as the explicit-export path, scoped to intentional
  finalization rather than routine viewing.

#### Rationale
Separates "configuration I want to reuse" from "a specific numeric result
I need to preserve as evidence of what was produced," which are genuinely
different needs with different staleness tolerances: a definition *should*
track its run's current data by design (no drift, ADR-008's single-source-
of-truth principle), while an exported record *should not* silently change
after the fact. Gating persistence behind an explicit action also prevents
the routine-viewing artifact sprawl that shaped ADR-008 and ADR-009's
persistence limits.

#### Consequences
- Saved table definitions need their own small storage location (e.g.
  `outputs/tables/definitions/` or similar — exact placement deferred to
  the folder/file schema specification), distinct from `outputs/tables/`
  where exported snapshots land.
- The reporting/table-builder needs its own version identifier, separate
  from `STBAM_MODEL_VERSION`, tracked wherever definitions and exports
  record provenance — a new piece of shared infrastructure alongside the
  content-hashing (ADR-008) and peak-finding (ADR-009) utilities already
  identified.
- "Add to report" (mentioned by the user as a possible future export path
  alongside Export/Save snapshot) is noted as a likely third trigger for a
  frozen snapshot, feeding a future Word/report-assembly mechanism — not
  specified further here.

#### Scientific implications
None directly — this is a provenance/persistence-architecture decision.
It materially supports scientific defensibility: an exported table used in
a regulatory record stays exactly reproducible-as-produced, while live
definitions never present numbers that have silently fallen out of sync
with their source run.

#### Open follow-ups
- Exact folder placement for definitions vs. exported snapshots — file/
  folder schema specification.
- Reporting/table-builder version identifier scheme — implementation
  phase, alongside `STBAM_MODEL_VERSION`.
- "Add to report" mechanics — deferred to a future report-assembly
  design, not blocking this decision.

---

### ADR-013 — Figure architecture: one switchable grouped/individual/raw drill-down hierarchy, orthogonal to a separate multi-series comparison dimension; definition/live-render/export-snapshot pattern matching ADR-012

Status: Accepted

#### Context
Decision 13 asked how one figure represents a crop reporting group. The
user chose option B (switchable levels) and substantially extended it:
level-of-detail (grouped/individual/raw) and series/comparison selection
(what is being compared — crops, rates, receptors, assumption sets, runs,
exposure characterizations) are **two independent architectural concepts**,
not one setting, and the whole figure system must apply the same
definition/live-render/export-snapshot separation just adopted for tables
in ADR-012.

#### Decision

**Two orthogonal axes, not one setting:**

```text
LEVEL OF DETAIL (drill-down hierarchy)
  Grouped   -> e.g. a min-max envelope across a reporting group's
               contributing crops/scenarios (ADR-010/011)
  Individual -> selected individual crop (or other entity) trajectories
  Raw        -> selected underlying model scenarios

SERIES / COMPARISON DIMENSION (what is plotted side by side)
  crop or reporting group, rate, receptor, assumption set, run,
  exposure characterization (conditional vs. maximum-obtainable), etc.
```

A figure definition sets a level of detail (which determines *how* each
series is rendered — envelope, line, or raw trace) and, independently, one
or more selected series (which determines *what* is compared). E.g.
"Grouped level, two series: Small Cereals under 2020 seeding assumptions
vs. Small Cereals under 2026 seeding assumptions" (two envelopes, one
plot), or "Individual level, four series: Barley/Wheat/Oat/Rye" (four
trajectories, one plot). This is a **drill-down hierarchy within one
analytical figure**, not three disconnected figure types (per the earlier
"Grouped -> Individual -> Raw" diagram the user gave), and it is explicitly
designed to replace the current architecture's proliferation of hundreds
of separately generated static figures.

**Grouped-envelope semantics.** For time-dependent grouped results, the
envelope is a min-max band. The figure and its accompanying metadata/
footnote must state explicitly that the scenario driving the upper or
lower bound **may change over the time axis** — the envelope must never be
presented as if either edge were the trajectory of one single continuous
crop/scenario. ADR-011's bound-identity data (`min_scenario_id`/
`max_scenario_id`, tie flags, `grouped_result_bounds`) is the mechanism a
reviewer uses to identify, and drill down to, whatever is currently
driving a given bound.

**Individual and raw views never auto-plot everything.** Neither level
defaults to rendering every available crop or every available raw
scenario; both require the user to select which series appear (see UX
controls below), specifically to avoid recreating an unreadable, all-
combinations figure.

**Recommended (non-blocking) UX controls for series selection**, proposed
here as a direction for the detailed design phase rather than a decision
this ADR fixes:
- At the individual level: explicit multi-select of crops/entities, with
  convenience shortcuts such as "crops currently driving the group's min/
  max envelope" (directly sourced from ADR-011 bound identity) and
  "selected focal crops," plus an "all" option gated by a soft warning
  (not a hard block) once the count is large enough to risk unreadability.
- At the raw level: explicit selection of specific scenario IDs, reached
  by drilling down from a grouped or individual view (e.g. clicking a
  bound or a trajectory) rather than browsing the full raw table cold.
- A general "would this be readable" guard (e.g. a soft warning, not a
  hard limit) when a user's selected series count or combination is likely
  to produce a cluttered or scientifically confusing figure — exact
  thresholds/heuristics are implementation-phase design, not fixed here.

**Interactive exploration vs. export.** The switchable levels and series
selection are Shiny exploration/review capabilities operating on one live
figure. An explicit export captures exactly the current analytical view —
level of detail, selected series, filters, grouping scheme, metric, time
selection (key days / custom days / range — per ADR-009), and display
settings — as of that moment. Exporting one figure produces exactly the
one view currently configured; it never automatically generates every
combination or all three detail levels, which is precisely the volume
problem this decision is designed to eliminate.

**Persistence — mirrors ADR-012 exactly, applied to figures:**

```text
Preserved run results
        |
        v
Saved figure definition
  - metric, detail level, comparison series,
    grouping scheme, filters, time selection,
    display settings
        |
        v
Live Shiny figure (recomputed/re-rendered from the run each time)
        |
        +----> explicit export
                    |
                    v
             frozen PNG/SVG/etc. snapshot
```

A saved figure definition is a small, reusable, editable specification
(not a rendered image, not a duplicated data extract) sufficient to
recreate the exact analytical view from the preserved run's raw/grouped
results. A rendered image becomes a persisted artifact only via an
explicit export action, exactly as ADR-012 established for tables — same
provenance requirements apply (source `run_id`, the figure definition/
configuration, generation date/time, model version, and a reporting/
figure-builder version tracked separately from `STBAM_MODEL_VERSION`, for
the same reasons given in ADR-012).

#### Alternatives considered
- A (separate fixed-level figures) — superseded; does not meet the
  drill-down requirement or the multi-series comparison requirement.
- C (always-composite overlay of all three levels) — superseded; risks
  the unreadability the user explicitly wants avoided, and does not
  support independent series comparison (two envelopes, or four
  individual trajectories) which the composite framing does not
  naturally express.
- A single combined "detail + series" setting (the original framing of
  option B before this refinement) — superseded; the user identified this
  conflates two independent choices and would make comparisons like "two
  grouped envelopes side by side" awkward to express.

#### Rationale
Splitting level-of-detail from series/comparison is what makes both
requirements simultaneously satisfiable: a drill-down hierarchy (so a
reviewer moves fluidly from a concise grouped view to its constituents)
and flexible multi-series comparison (so scientifically meaningful
side-by-side comparisons — assumption sets, rates, receptors, runs,
exposure characterizations — aren't limited to whatever single series a
"detail level" happens to imply). Matching ADR-012's definition/live-
render/export-snapshot pattern for figures (rather than inventing a
different persistence model for figures vs. tables) keeps the redesign's
persistence architecture uniform across both presentation-artifact types.

#### Consequences
- The figure-rendering layer needs to accept, independently: a detail
  level, one or more series specifications, and a rendering mode per
  detail level (envelope for grouped, line/trajectory for individual, raw
  trace for raw) — a materially different interface than the current
  `35_max_obtainable_plots.R`'s per-scenario plotting functions, to be
  designed in the implementation-phase figure-generation specification.
- Envelope figures need an accompanying, mandatory footnote/metadata
  statement about bound identity potentially changing over time —
  extending the existing `format_figure_footnotes()` pattern.
- Series-selection UX (multi-select, "drivers of the envelope" shortcut,
  soft unreadability warnings) becomes part of the Shiny information-
  architecture specification (§21 deliverable), not fixed further here.
- A figure-builder version identifier is needed, parallel to the
  reporting/table-builder version identifier from ADR-012.

#### Scientific implications
None directly — this is a presentation-architecture decision. It
materially strengthens scientific communication clarity: the explicit
requirement that an envelope not imply one continuous driving scenario
directly prevents a plausible visual misreading of a min-max band.

#### Open follow-ups
- Exact series-selection UX and unreadability-guard heuristics —
  implementation-phase Shiny information-architecture specification.
- Exact figure-definition and export-snapshot folder placement — file/
  folder schema specification, alongside ADR-012's equivalent follow-up.
- Figure-builder version identifier scheme — implementation phase.
- Exact rendering-library/mechanism choice for envelope figures (e.g.
  ribbon/band plotting) — implementation-phase figure-generation
  specification, not an architecture decision.

---

### ADR-014 — Shiny navigation: evaluation picker/landing screen with Create/Open/Clone/Rename/Delete, entering a dedicated per-evaluation workspace

Status: Accepted

#### Context
ADR-002 established that an evaluation folder is the unit the Shiny GUI
creates, opens, edits, runs, and reloads, but left open exactly how a user
navigates to and between evaluations. Decision 14 settled this.

#### Decision
The app opens to an **evaluation picker/landing screen**: a list of
existing evaluations, scanned from `evaluations/`, with Create, Open,
Clone, Rename, and Delete actions available directly on that screen.
Selecting or creating an evaluation navigates into a **dedicated
per-evaluation workspace view** (inputs editing, runs, grouped results,
tables, figures — per ADR-004 through ADR-013). The user can return to the
picker at any time to switch to a different evaluation, without
restarting the app. Only one evaluation is open/active in the workspace
at a time.

#### Alternatives considered
- A (folder-picker startup, single-evaluation session, restart to switch)
  — superseded: no natural home for evaluation-level management actions
  (create/clone/rename/delete), and restarting to switch evaluations is
  needless friction the picker screen avoids.
- C (multiple evaluations open simultaneously, e.g. tabs) — superseded
  for now: adds session-state complexity for a cross-evaluation
  comparison need that is not yet established as required, given
  within-evaluation comparison (across runs, assumption sets, reporting
  groups) is already substantially supported by ADR-013's series-
  comparison dimension.

#### Rationale
Matches the "self-contained, clonable, deletable folder" model already
adopted for evaluations (ADR-002/ADR-003): a landing screen is the natural
place for whole-evaluation lifecycle actions that don't belong inside any
single evaluation's own workspace, while keeping the per-evaluation
workspace itself simple (exactly one evaluation's state at a time).

#### Consequences
- The picker screen needs a lightweight way to enumerate evaluations
  (scan `evaluations/*/`) and surface minimal identifying metadata (name,
  last-modified, perhaps last-run date) without loading each evaluation's
  full state — implementation detail for the Shiny information-
  architecture specification.
- Clone/Rename/Delete on the picker screen are the natural place to
  enforce the "evaluation folder is the single movable/copyable/
  deletable unit" invariant already anticipated in ADR-002.
- If cross-evaluation comparison becomes a real requirement later, it is
  treated as a new, explicit feature (e.g. a comparison view that reads
  from two evaluations' preserved runs) rather than reopening this
  single-active-evaluation navigation model.

#### Scientific implications
None. Pure GUI-navigation decision.

#### Open follow-ups
- Exact picker-screen layout and metadata shown per evaluation —
  Shiny information-architecture specification (§21 deliverable).
- Whether/how Clone offers to also clone or reset run history — not
  decided here; likely defaults to "clone inputs only, no runs," but
  deferred to implementation-phase design.

---

### ADR-015 — Migration: one-time automated script converts the existing project into the first evaluation

Status: Accepted

#### Context
ADR-001 deferred migration explicitly: "the current thiamethoxam project
becomes the first (and for now, only) assessment workspace under the new
architecture." Decision 15 settled the mechanism. Most of migration is
already implied by decisions already made — ADR-003's copy-on-create
behaviour and ADR-004's named-set folders together account for almost all
of `data/reference/`'s content with no new logic required. The one
genuinely new transformation is `scenario_definitions.csv` into the
normalized `use_patterns.csv` shape from ADR-005 (adding `use_id`, one row
per atomic use condition).

#### Decision
A **one-time, re-runnable migration script** performs the conversion:
1. Creates the first evaluation folder (name to be chosen at
   implementation time, e.g. reflecting "thiamethoxam") via the same
   mechanism ADR-014's Create action would use.
2. Populates each ADR-004 named-set category with a single set (e.g.
   named "default" or similarly descriptive) containing today's
   `data/reference/*.csv` content for that category, unchanged in value.
3. Transforms `scenario_definitions.csv` into a normalized
   `use_patterns.csv` per ADR-005's schema (`use_id`, crop, rate + unit,
   planting method as separate rows sharing one `use_id` where
   applicable).
4. Is re-runnable and testable: its output is checked against the
   invariant that recomputing `scenario_inputs`/`scenario_summary` from
   the migrated evaluation reproduces results identical to today's
   canonical outputs (ties into the "architectural invariants to test"
   requirement from the original request, and the general reproducibility
   discipline established throughout ADR-008/009).

#### Alternatives considered
- B (manual/GUI recreation) — superseded: the one nontrivial
  transformation (`scenario_definitions.csv` -> `use_patterns.csv`) is
  exactly the kind of small, mechanical, precisely-specified conversion a
  script performs more reliably than manual re-entry, which risks
  transcription error with no independent check.
- C (parallel operation during transition) — superseded: migration here
  is a data-format conversion with an automatable, verifiable outcome, not
  an ongoing capability gap that requires running two apps side by side.

#### Rationale
Every input the migration script needs to produce is already fully
specified by prior decisions (ADR-003, ADR-004, ADR-005), so a script is
both the most reliable path and the cheapest to verify — its correctness
reduces to "does recomputing from the migrated evaluation reproduce
today's canonical outputs," a concrete, automatable test rather than a
subjective review of manually re-entered data.

#### Consequences
- The migration script becomes a natural first piece of implementation
  work, and a natural first end-to-end test of the whole new architecture
  (folder creation, named sets, use-pattern normalization, and
  recomputation) before any GUI work is built on top of it.
- Migration is a one-time event for the current project; the script does
  not need to be a permanently maintained, general-purpose "any project ->
  evaluation" importer, though nothing here precludes reusing its logic if
  a second legacy project ever needed the same treatment.
- The exact target evaluation name and the "default" set-naming convention
  are implementation-phase decisions, not fixed by this ADR.

#### Scientific implications
None directly, provided the reproducibility invariant (identical
`scenario_inputs`/`scenario_summary` before and after migration) holds —
this ADR makes that invariant a required, testable gate on migration
itself, not an optional check.

#### Open follow-ups
- Exact migrated evaluation name and default-set naming convention —
  implementation phase.
- Whether any existing session-exported override configurations (from the
  current `export_scenario_config()` mechanism, if any exist on disk)
  represent real work product needing conversion into named assumption
  sets, or whether none currently exist outside the reference defaults —
  to be confirmed during implementation by checking the actual repository
  state at that time.
- Migration script becomes the first concrete test of the reproducibility
  invariant referenced in the original request's invariant list —
  captured in the invariants/test-plan deliverable (§21).

---

### ADR-016 — Table 162 support: deferred porting; legacy module preserved; source provenance clarified

Status: Accepted

#### Context
`docs/planning/implementation_readiness_review.md` found that the current
Shiny application's "Table 162 support" tab (`R/summaries/24_table162_support.R`,
`R/shiny/41_modules_results.R`'s `mod_table162_*`) is not mentioned anywhere
across the twelve planning documents produced during the architecture
phase, and that its only crop-grouping data
(`STBAM_WORKBOOK_TO_CROP_FAMILY`) is a hard-coded R constant, not a CSV —
exactly what ADR-010's `reporting_sets/` is meant to replace. The user was
asked to resolve this gap and also clarified, during the same exchange,
that the actual Table 162 lives in an assessment Word document in the
sibling document-review project
(`C:\MonDossierMartin\Python_Local\Python_Document analysis\THE BAM ST RA
- interim draft TABLES and FIGS - LIVE.mdlAug26.docx`), independently
verified this session: SHA-256
`ea76adfa0044db808867d880325a1932b891a1d72566f4a8c7b8752a0a36fb6a`, which
matches the sibling project's own pinned baseline for this file (its
`PROJECT_STATE.md`, ID `TABLES`) exactly. The current project's
`table162_decision_matrix.csv`/`table162_considerations.csv` (per
`copied_register_manifest.csv`) are copies of reviewer-built registers
(`03_registers/*.csv` in the sibling project) *derived from* that
document during document-analysis work — not the document itself, and not
guaranteed to be a complete restatement of it.

#### Decision
1. **Table 162 support is explicitly deferred**, not dropped, from Phases
   0–7 of this redesign. No phase in `implementation_phases_proposal.md`
   is required to build a redesigned Table 162 Shiny module, and Phase
   2's migration-equivalence gate does **not** require Table 162 parity.
2. **Existing Table 162-related CSV/register data and its provenance are
   preserved through migration** (`table162_decision_matrix.csv`,
   `table162_considerations.csv`, `review_core_assumptions.csv`,
   `review_effects_metrics.csv`, `copied_register_manifest.csv`,
   `source_manifest.csv`) — copied unchanged into the migrated
   evaluation's `inputs/reference/` (`folder_and_input_schema.md` §1),
   per the corrected migration inventory (`migration_plan.md`, revised
   this session).
3. **The Word document above is recorded as the upstream source** for
   Table 162 material, distinct from the copied CSV registers, which are
   recorded as reviewer/document-analysis artifacts *derived from* it —
   not treated as an interchangeable substitute for it. See ADR-018 for
   the general four-tier provenance model this establishes.
4. **`STBAM_WORKBOOK_TO_CROP_FAMILY` is extracted, unchanged in value,
   into an initial `reporting_sets/` scheme** (e.g. `crop_family.csv`)
   during migration, so the new architecture starts with equivalent
   crop-grouping capability even before any Table 162 redesign — this is
   grouping-scheme content the new architecture already needs generally
   (ADR-010), independent of whether Table 162 itself is ever redesigned.
5. **The existing Table 162 Shiny module remains available as legacy
   functionality** for as long as the legacy application itself remains
   available (ADR-020) — it is not removed as a side effect of any Phase
   0–7 work.
6. **A later, explicitly-scoped checkpoint/ticket is created for Table
   162 redesign/porting**, to be planned only once the new evaluation/
   run/reporting-group architecture (Phases 1–5) is stable, and grounded
   in what Table 162 actually represents in the assessment document
   itself (crop family x rate x planting method x taxon x effect-window
   x receptor-size decision cells, per
   `data/reference/table162_decision_matrix.csv`'s own schema) — not
   merely in the current R implementation's structure. This checkpoint is
   not scheduled to a specific phase number by this ADR; it is logged as
   an explicit future decision point, not an assumption that Phase 7
   covers it.

#### Alternatives considered
- Mechanically port the current Table 162 module during Phase 1/2 as a
  sixth "assumption-adjacent" screen — rejected: expands the core
  evaluation/run architecture's scope before it is proven, and risks
  building a redesigned module around the current copied-register
  structure rather than around the actual source document.
- Drop Table 162 support entirely from the redesign's scope — rejected:
  the user explicitly stated it is useful and must not disappear.
- Leave it unaddressed (the state this ADR corrects) — rejected: leaves
  "when can the legacy app be retired" permanently unanswerable.

#### Rationale
Separates "does not enlarge Phase 0–7's scope" from "is preserved and
will be redesigned later, deliberately" — the two things the user asked
for are not in tension once stated as separate commitments with separate
timing.

#### Consequences
- Migration (Phase 2) must copy the Table 162-related CSVs and extract
  `STBAM_WORKBOOK_TO_CROP_FAMILY`, but is not blocked on, or measured
  against, any Table 162 Shiny functionality.
- The legacy-app retirement decision (ADR-020) cannot approve removing
  Table 162 support until its dedicated redesign checkpoint (or an
  explicit decision to drop it) is reached.
- A future Table 162 redesign should start from the Word document's own
  structure (crop family/rate/method/taxon/effect-window/receptor-size
  decision cells) and the reviewer registers' documented relationship to
  it, not from `R/summaries/24_table162_support.R`'s current joins.

#### Scientific implications
None directly — this is a scope/sequencing and provenance decision. It
does protect scientific traceability: the actual source document and the
derived registers are no longer at risk of being conflated during a
future redesign.

#### Open follow-ups
- Exact timing/phase-number for the Table 162 redesign checkpoint — not
  fixed by this ADR, deliberately.
- Whether the redesigned Table 162 module reads the Word document's
  content directly (e.g. via a future structured extraction) or continues
  to rely on the reviewer registers as its working representation — a
  question for that future checkpoint, not this one.

---

### ADR-017 — Sensitivity analysis: deferred porting, reconsidered after named-set/run/comparison architecture matures

Status: Accepted

#### Context
Like Table 162 support, the current "Sensitivity" tab
(`R/shiny/42_module_sensitivity.R`, one-at-a-time override-based parameter
sweeps) is not mentioned anywhere in the twelve planning documents. The
user confirmed this is a deferral, not an oversight, and identified a
specific reason: the new architecture's named assumption sets (ADR-004),
preserved runs (ADR-008), and multi-run/multi-set comparison capability
(ADR-013's series dimension) may ultimately provide a more transparent
way to explore sensitivity than the current session-override-based sweep,
once that infrastructure actually exists to compare against.

#### Decision
1. **Sensitivity is explicitly deferred**, not mechanically ported, during
   Phases 0–7. No phase requires a redesigned Sensitivity module, and
   Phase 2's migration-equivalence gate does not require Sensitivity
   parity.
2. **The existing Sensitivity tab remains available as legacy
   functionality** for as long as the legacy application remains
   available (ADR-020).
3. **Reconsideration is deferred until after** the named assumption-set
   architecture (Phase 1), preserved-run architecture (Phase 3), and
   multi-run/multi-set comparison capability (Phase 6, via ADR-013's
   series dimension) are working — at that point, the natural question
   becomes "does comparing complete named sets/runs already cover what
   the override-sweep provided, or is a lower-friction one-parameter
   sweep still independently useful," which cannot be answered until
   that comparison capability exists to evaluate against.
4. No phase number is assigned to a Sensitivity redesign by this ADR — it
   is logged as a deferred capability (see the "Deferred capabilities"
   section added to `implementation_phases_proposal.md` this session),
   revisited after Phase 7, not assumed to be silently dropped.

#### Alternatives considered
- Port the current override-based sweep unchanged into the new
  architecture during Phase 1/3 — rejected: the override concept is
  exactly what this redesign replaces (see the "Why this redesign"
  section at the top of this document); porting it mechanically would
  reintroduce the pattern the rest of the redesign eliminates.
- Drop Sensitivity permanently — rejected: the user stated the underlying
  capability (understanding result sensitivity to assumptions) remains
  useful; only the current mechanism's fit is in question.

#### Rationale
The current Sensitivity mechanism is architecturally tied to the
session-override model this redesign retires. Redesigning it before the
replacement comparison primitives (named sets, runs, series) exist would
either recreate the override pattern inside the new architecture or
require guessing at a design that Phase 6's actual comparison UX should
inform directly.

#### Consequences
- No Sensitivity-equivalent capability exists in the new architecture
  until an explicit future phase addresses it; users needing one-at-a-
  time parameter sweeps use the legacy app in the meantime (ADR-020).
- When reconsidered, the design question is no longer "how do we port
  this tab" but "does named-set/run comparison already subsume this, and
  if not, what residual capability is still needed" — a materially
  different and better-informed question than could be answered today.

#### Scientific implications
None directly. Preserves an existing, validated analysis capability
without foreclosing whether it is best served by a ported tab or by the
new comparison architecture.

#### Open follow-ups
- Exact timing/phase-number for reconsideration — deliberately not fixed
  here; logged as a deferred capability, revisited after Phase 7.

---

### ADR-018 — Source-document provenance model: four tiers, distinguished explicitly; large originals referenced, not duplicated

Status: Accepted

#### Context
The user clarified that this R project's working directory
(`C:\MonDossierMartin\R\seed_treatment_bam_model`) is not where the
original assessment source material lives — that material is in a
sibling project (`C:\MonDossierMartin\Python_Local\Python_Document
analysis`), and this project's `data/reference/*.csv` files are
extractions/copies, not originals. The user asked that four categories of
material be kept explicitly distinct throughout the redesign, and that
original source material in the sibling project never be modified as part
of this work, nor automatically duplicated into every evaluation.

Verified this session (read-only; no sibling-project file was modified):
`data/reference/source_manifest.csv` records 6 original calculation
workbooks by bare filename + SHA-256, without a stored folder path. All 6
were located in the sibling project and their SHA-256 hashes independently
recomputed and confirmed to match the manifest exactly:

| `workbook_key` | Role | Verified full path (sibling project) |
|---|---|---|
| `small_cereals` | `PRIMARY_AUDITED_REFERENCE` | `Documents\Calculation Workbooks\THE 1 small cereals Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026.xlsm` |
| `small_cereals_msa` | `SCENARIO_SOURCE` | `Documents\THE 1b small cereals Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |
| `canola` | `SCENARIO_SOURCE` | `Documents\THE 2 canola rapeseed mustard Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |
| `legumes_deep` | `SCENARIO_SOURCE` | `Documents\Calculation Workbooks\THE 3 deep legumes Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |
| `legumes_shallow` | `SCENARIO_SOURCE` | `Documents\Calculation Workbooks\THE 3 shallow legumes Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |
| `cucurbits` | `SCENARIO_SOURCE` | `Documents\Calculation Workbooks\THE 5 cucurbits Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm` |

(all paths relative to `C:\MonDossierMartin\Python_Local\Python_Document
analysis\`). **Correction to the user's own message**: the path supplied
for "small cereals" is actually `small_cereals_msa` (`SCENARIO_SOURCE`) —
the `PRIMARY_AUDITED_REFERENCE` small-cereals workbook is the un-suffixed
"THE 1" file, under a different subfolder (`Calculation Workbooks\`, not
`Documents\` directly). The `canola` path supplied matches exactly. The
Table 162 Word document
(`THE BAM ST RA - interim draft TABLES and FIGS - LIVE.mdlAug26.docx`,
sibling project root) was also verified: SHA-256
`ea76adfa0044db808867d880325a1932b891a1d72566f4a8c7b8752a0a36fb6a`, which
matches the sibling project's own `PROJECT_STATE.md`-pinned baseline for
this exact file (ID `TABLES`) exactly.

#### Decision
Four tiers of material are distinguished explicitly, everywhere provenance
is recorded in this architecture, and never conflated:

1. **Original assessment source files** — the 6 `.xlsm` calculation
   workbooks and the assessment Word document(s), all in the sibling
   project, all read-only from this project's perspective. Never
   modified by any tool in this redesign.
2. **Extracted/reference data** — `data/reference/*.csv`'s 7
   assumption-category files (`crop_seeding_parameters.csv`,
   `scenario_definitions.csv`, `planting_method_parameters.csv`,
   `receptor_parameters.csv`, `fir_regressions.csv`,
   `effects_metrics.csv`, `dissipation_parameters.csv`), produced by
   `scripts/extract_reference_data.py` from tier 1, with SHA-256
   provenance in `source_manifest.csv`.
3. **Reviewer/document-analysis registers** — `review_core_assumptions.csv`,
   `review_effects_metrics.csv`, `table162_considerations.csv`,
   `table162_decision_matrix.csv`, copied from the sibling project's own
   `03_registers/` (per `copied_register_manifest.csv`), themselves
   *derived from* tier 1 by that project's independent review process —
   not a mechanical extraction of tier 1, and not guaranteed complete
   relative to it.
4. **Calculated R-model outputs** — every canonical dataset this project
   computes (`scenario_inputs`, `scenario_summary`, `daily_timecourse`,
   `table162_support`, and the new architecture's `key_day_results`/
   `grouped_results`) — always clearly downstream of tiers 1-3, never
   itself treated as a source.

**Original, large binary source documents (tier 1) are never automatically
copied into every evaluation.** An evaluation's `inputs/reference/`
(`folder_and_input_schema.md` §1) holds tier-2/tier-3 material (small,
plain-text CSVs, already the project's existing convention) plus
**provenance metadata referencing tier-1 originals by path and SHA-256** —
not the original files themselves. This extends the existing
`source_manifest.csv` pattern (already path-free/hash-only for the
workbooks) rather than introducing a new duplication mechanism, and keeps
evaluations self-contained *for reproducibility purposes* (the recorded
hash proves which original was used) without inheriting multi-megabyte
`.xlsm`/`.docx` files into every evaluation folder.

#### Alternatives considered
- Copy original `.xlsm`/`.docx` files into each evaluation's
  `inputs/reference/`, mirroring the CSV-copy pattern used for tiers 2-3
  — rejected: no functional benefit over path+hash referencing (the
  originals are never edited by this project, so a copy cannot diverge
  usefully from the sibling project's own copy), while materially
  increasing evaluation folder size (an `.xlsm` workbook can be
  megabytes; the Table 162 Word document is ~1.1MB) for content that
  provides no additional reproducibility guarantee beyond its hash.
- Treat tier-3 registers as equivalent to tier-1 originals — rejected:
  explicitly what the user asked to avoid; a register can be incomplete
  or interpretive relative to its source document in ways a hash-verified
  copy of the source itself cannot be.

#### Rationale
Matches the existing `source_manifest.csv` convention (hash-based
provenance, not file duplication) and the user's explicit instruction to
recommend "the cleanest reproducibility approach rather than assuming
duplication of the original files," while making the four-tier
distinction structural (recorded provenance fields) rather than a
convention that could silently erode over time.

#### Consequences
- `folder_and_input_schema.md`'s `inputs/reference/` description is
  updated (this session) to state this path+hash referencing pattern
  explicitly, distinguishing it from the wholesale-copy pattern used for
  tiers 2-3.
- `migration_plan.md` is updated (this session) to record the
  hash-verified tier-1 paths above as provenance metadata, without
  copying the underlying files.
- Any future tooling that needs to *read* tier-1 content directly (e.g. a
  future structured Table 162 extraction, ADR-016) does so by resolving
  the recorded path against the sibling project at read time — not by
  assuming a local copy exists inside the evaluation.

#### Scientific implications
None directly — this is a provenance-recording decision. It strengthens
scientific traceability by making the tier-1/tier-2/tier-3/tier-4
distinction explicit and checkable (hash verification), rather than
implicit in file naming conventions.

#### Open follow-ups
- If the sibling project's directory ever moves or is reorganized, the
  recorded tier-1 paths in this project's provenance metadata become
  stale and need a re-verification pass — not an issue this ADR resolves,
  since the sibling project is outside this project's control, but worth
  noting for future maintainers.

---

### ADR-019 — Independent-review policy: risk-based, mandatory for a named set of high-risk change categories

Status: Accepted

#### Context
`implementation_phases_proposal.md` §9 asked whether independent-review
gates should apply to every phase or only specific higher-risk phases,
without resolving it. The user resolved it: every phase gets ordinary
automated tests, explicit acceptance criteria, and a human review/approval
gate; a *separate, independent/adversarial agent review* (matching the
methodology already used for `docs/independent_engine_audit.md` and
`docs/max_obtainable_exposure_review.md`) is additionally mandatory only
for a specific, named list of high-risk change categories.

#### Decision
**Every implementation ticket, in every phase**, requires: automated
tests appropriate to that ticket; explicit acceptance criteria; a human
review/approval gate before proceeding.

**Independent adversarial agent review is additionally mandatory** for
any change falling into at least one of these categories:
1. Peak/key-day calculation logic where scientific result semantics are
   involved (Phase 0's peak-finder; Phase 3's `key_day_results` builder).
2. The evaluation-input → engine-parameter-set adapter (new, Phase 2 —
   see the migration plan revision this session).
3. Migration equivalence (Phase 2's full gate).
4. Run freezing/persistence and reproducibility (Phase 3: `inputs_snapshot`,
   content-hash/dedup logic).
5. Aggregation/range logic and min/max bound traceability (Phase 4:
   `grouped_results`, tie handling).
6. Grouped/time-dependent envelope calculations (Phase 6a: grouped-detail
   figure rendering).
7. Figure traceability where multiple runs/assumption sets are compared
   (Phase 6b: multi-series/multi-run figure selection).

**Routine, low-risk GUI/layout or plumbing tickets** (e.g. picker-screen
layout, `DT` grid wiring, Excel export button placement) do **not**
individually require independent review, unless implementation evidence
(a failing test, a reviewer's own doubt, an unexpected edge case) raises a
specific concern for that ticket — at which point it is escalated the same
way any concern would be, not because of a blanket category rule.

#### Alternatives considered
- Mandatory independent review for every single ticket — rejected by the
  user as disproportionate for routine plumbing/layout work, and a likely
  source of review fatigue that would dilute scrutiny on the categories
  that actually matter.
- Independent review only at whole-phase gates (Phase 2, Phase 3, as the
  original proposal's §9 suggested as one option) — superseded: too
  coarse: e.g. Phase 3 contains both the content-hash/dedup logic
  (high-risk, category 4 above) and the Runs-screen UI (low-risk), which
  should not share one review-or-not decision.

#### Rationale
Matches the risk actually present in each category: categories 1-7 above
are exactly the places where a subtle defect could silently produce a
wrong scientific number, a non-reproducible run, or a misleading
aggregate/figure — the same class of risk `docs/independent_engine_audit.md`
and `docs/max_obtainable_exposure_review.md` were built to catch. Applying
the same discipline there, without applying it uniformly to every ticket,
keeps the review burden proportionate.

#### Consequences
- `invariants_and_test_plan.md` §3 is updated (this session) to state
  this risk-based list explicitly, replacing its more general prior
  language ("any phase that touches shared calculation-adjacent code").
- `implementation_phases_proposal.md` is updated (this session) to mark,
  per phase, which tickets fall into the mandatory-independent-review
  categories above.
- The reviewing agent for any category-1–7 change should have no prior
  authorship of the change under review, consistent with the existing
  audit methodology.

#### Scientific implications
None directly — this is a process/quality-assurance decision. It
directly protects I16 (engine semantics unchanged) and I9/I10/I11 (peak
correctness, reproducibility, migration equivalence) by concentrating
independent scrutiny exactly where those invariants could otherwise fail
silently.

#### Open follow-ups
None — the policy is fully specified above; applying it to identify each
phase's specific in-scope tickets is implementation-phase bookkeeping, not
a further architecture decision.

---

### ADR-020 — Legacy Shiny application retirement: no automatic retirement at any single phase gate; decided at a dedicated later checkpoint

Status: Accepted

#### Context
`implementation_dependencies_and_risks.md` and
`implementation_phases_proposal.md` both flagged "what happens to the old
override-based app" as an open cross-cutting risk without a firm decision
point. `docs/planning/implementation_readiness_review.md` recommended
splitting "informal steer toward the new app" (after Phase 2) from
"formal code retirement" (after Phase 7). ADR-016 and ADR-017 now add a
concrete reason formal retirement cannot happen automatically after any
single early phase: the legacy app is the only home for Table 162 support
and Sensitivity analysis until their own, separately-scheduled
checkpoints are reached.

#### Decision
1. **No phase gate (0 through 7) authorizes deleting or disabling the
   legacy Shiny application.** Completing Phase 2 (migration) in
   particular does **not** imply the legacy app can be retired — it only
   means a migrated evaluation exists that the new app can operate on
   alongside the legacy app's continued availability.
2. **Informal user guidance may shift toward the new app once Phase 2 is
   complete** (a real, migrated evaluation exists to work in), but this is
   a usage recommendation, not a retirement of the legacy code.
3. **Formal retirement is decided at a dedicated later checkpoint**,
   reached only once:
   - Phase 7's full manual acceptance walkthrough passes (new app
     demonstrates working Inputs/Runs/Results/Tables/Figures end-to-end);
     and
   - Table 162 support and Sensitivity have each reached their own
     explicit disposition (ADR-016, ADR-017) — either redesigned/ported
     with demonstrated parity, or explicitly, separately decided as
     permanently legacy-only.
4. **No legacy feature is retired merely because it was absent from the
   initial redesign specifications.** Absence from Phases 0-7's scope
   means "not yet redesigned," never "safe to delete."

#### Alternatives considered
- Retire the legacy app immediately after Phase 2 (migration), per the
  original proposal's more speculative framing — rejected: leaves users
  without a working Table 162/Sensitivity/Results-viewing surface for the
  several phases between Phase 2 and Phase 7.
- Leave the retirement decision entirely open with no checkpoint at all
  (the state this ADR corrects) — rejected: gives "when can we delete the
  old app" no answerable stopping condition.

#### Rationale
Ties legacy retirement to demonstrated functional parity (Phase 7's
walkthrough) plus explicit disposition of every capability the legacy app
uniquely provides (Table 162, Sensitivity) — rather than to an arbitrary
phase number, which would risk removing the users' only working tool for
a capability that hasn't actually been replaced yet.

#### Consequences
- The legacy app (`app/app.R`, `R/shiny/4*.R`) is not modified or removed
  by any Phase 0-7 ticket.
- `implementation_phases_proposal.md` is updated (this session) to state
  this checkpoint explicitly as a "Deferred capabilities and legacy
  retirement" section, rather than leaving it implicit in Phase 2's notes.
- The dedicated retirement checkpoint itself is not assigned a phase
  number by this ADR — it follows Phase 7 and the Table 162/Sensitivity
  checkpoints, whichever is later.

#### Scientific implications
None directly. Protects continuity of validated, currently-relied-upon
functionality (Table 162 support, Sensitivity) throughout the redesign.

#### Open follow-ups
None — the checkpoint's precondition is fully specified above; its exact
calendar timing depends on how Phases 0-7 and the Table 162/Sensitivity
checkpoints actually proceed.

---

### ADR-021 — `planting_method_sets` is its own named-set category, ratifying the Phase 1 implementation finding

Status: Accepted

#### Context
ADR-004's folder tree and `folder_and_input_schema.md` §1/§2.2 named five
named-set categories (`seeding_sets`, `receptor_sets`, `effects_sets`,
`fate_sets`, `reporting_sets`) and left the destination of
`data/reference/planting_method_parameters.csv` (surface-seed fraction by
planting method) as an explicit two-way open choice in `migration_plan.md`
§7: fold it into `seeding_sets`, or give it "its own file within
`agronomy/`." Neither option anticipated a third, fully independent
named-set category with its own manifest and `set_id` provenance field.

During Phase 1 implementation, this was resolved a third way — as its own
category, `agronomy/planting_method_sets/` — per the human instruction
that planting method is scientifically load-bearing and must not be
demoted to metadata folded into another category
(`R/evaluations/50_schema_registry.R`'s `stbam_schema_planting_method_sets()`,
`PROJECT_STATE.md`'s Phase 1 section). This ADR ratifies that
implementation-time decision in the planning record; it does not
authorize any further architecture change.

This resolution was checked, before ratification, against every existing
ADR and schema passage that touches planting method:
- ADR-004's own folder tree never listed a planting-method category, so it
  is silent, not contradicted, by adding one.
- ADR-006's own decision text already anticipated a planting-method set as
  a validation target ("referential integrity such as crop names matching
  a planting-method set"), which is more consistent with a dedicated
  category than with folding the data into `seeding_sets`.
- ADR-005 (`use_patterns.csv`) references planting method by string label
  on each row, not by a set ID — unaffected either way, since
  `use_patterns.csv` was never going to carry a `planting_method_set_id`
  column itself (there is exactly one planting-method set per evaluation
  in the current model, propagated via ADR-004 point 6's general
  selected-set-identity mechanism, not via `use_patterns.csv`).

No accepted ADR is contradicted by this decision. It is a gap-filling
ratification, not a conflict resolution.

#### Decision
1. **`agronomy/planting_method_sets/` is the sixth named-set category**,
   alongside `seeding_sets`, `receptor_sets`, `effects_sets`, `fate_sets`,
   `reporting_sets` (ADR-004). Its folder path (relative to
   `inputs/assumptions/`) is `agronomy/planting_method_sets`, matching
   `STBAM_SET_CATEGORIES$planting_method_sets$path` as implemented.
2. **Schema**: one row per planting method, columns
   `planting_method_label`, `planting_method` (key; values restricted to
   `STBAM_PLANTING_METHODS`), `surface_seed_fraction` (0-1), `source`
   (optional — see point 3), `status`. Generalizes
   `data/reference/planting_method_parameters.csv` unchanged.
3. **A named set's `source` field is legitimately nullable at the
   per-row level, project-wide, not only for this category.** The live
   `data/reference/planting_method_parameters.csv`'s `broadcast` row
   carries a literal `NA` in `source` (`surface_seed_fraction = 1.0` is
   definitional, not citation-derived) — this is authoritative reference
   data, not a data-entry defect, so the schema must accept it rather than
   reject the project's own assessment default on first evaluation
   creation. `stbam_manifest_schema()`'s own `source` column was already
   optional for the same reason; this ADR extends that same treatment
   explicitly to any category schema's own row-level `source` column
   (currently only `planting_method_sets` has one), rather than leaving it
   as an unstated, category-specific implementation detail.
4. **`seeding_sets` keeps the planting-method *availability* booleans**
   (`spring_seeded`, `fall_seeded`, `broadcast_seeded`, `drill_seeded`,
   `precision_planted`) — these describe which methods are agronomically
   possible for a crop, a property of the crop, not of the method itself.
   `planting_method_sets` holds the method-level constant (surface-seed
   fraction), a property of the method, not of any one crop. The two
   categories are complementary, not overlapping.

#### Alternatives considered
- Fold `planting_method_parameters.csv` into `seeding_sets` (migration_plan.md
  §7's first option) — rejected: this would require repeating each crop's
  four rows' worth of per-crop data once per crop (a table with per-crop
  granularity absorbing method-level, not crop-level, data), and would
  prevent selecting a different planting-method assumption set
  independently of a seeding-parameters set, contrary to the human
  instruction that planting method is independently scientifically
  load-bearing.
- Treat it as non-set metadata (e.g. a fixed constant embedded in code or
  in the evaluation's top-level config, not a selectable set at all) —
  rejected: this is exactly the "override-era global constant" pattern
  ADR-004 was written to move away from, and would make a future
  alternative planting-method assumption set (e.g. a revised surface-seed
  fraction study) impossible to represent without another architecture
  change.

#### Rationale
A dedicated category keeps method-level science independently selectable
and versionable, matches how the human instruction characterized planting
method's scientific weight, and is at least as consistent with ADR-006's
own already-drafted validation language as either of the two alternatives
`migration_plan.md` §7 had left open.

#### Consequences
- `folder_and_input_schema.md` §1 (directory tree) and §2.2 (category
  schema table) are updated (this session) to list
  `agronomy/planting_method_sets/` as a sixth category and to state the
  `source`-nullability rule generally, rather than leaving both as an
  undocumented Phase 1 implementation detail.
- `migration_plan.md` §2.2 (destination table) and §7 (open items) are
  updated (this session) to mark this choice resolved, pointing at this
  ADR instead of restating it as still-open.
- `use_patterns.csv`'s own validation continues to check `planting_method`
  against `STBAM_PLANTING_METHODS` (a fixed enum), not against a
  `planting_method_sets` set ID — an evaluation is expected to have
  exactly one active planting-method set, consistent with how Phase 1
  implemented every other category before per-run "selected set" tracking
  exists (Phase 3).
- Phase 2 migration (ADR-015) populates `agronomy/planting_method_sets/`
  from `data/reference/planting_method_parameters.csv` using the same
  generic named-set population step used for every other category — no
  special-cased migration logic is required as a result of this ADR.

#### Scientific implications
None. This ADR records where data already used unchanged by the
validated engine is filed in the new architecture; it does not add,
remove, or alter any surface-seed-fraction value or the calculation that
consumes it.

#### Open follow-ups
None. The two `migration_plan.md` §7 open items this ADR closes
(planting-method-set placement; and, as a documented consequence, the
`source`-nullability rule) are both resolved above.

---
