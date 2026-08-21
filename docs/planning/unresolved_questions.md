# Unresolved-question register — assessment/workspace redesign

Companion to `docs/planning/assessment_workspace_architecture.md`. Kept
separate so scientific-judgement questions are never mixed into
software-architecture decisions, and so deferred items are not lost.

**Types:** Architecture · UX · Data · Reporting · Scientific · Migration ·
Validation

| ID | Question | Type | Status | Blocks implementation? |
|---|---|---|---|---|
| Q001 | Where does `evaluations/` live relative to the existing project root, `data/reference/`, and the current `outputs/` folder? | Architecture | Resolved (ADR-003) | No |
| Q002 | Does the central default template (`data/reference/`) need to support multiple named sets per category (mirroring evaluations' `*_sets/` folders), or does set variety only emerge once evaluations exist, via cloning/editing? | Architecture | Open | Not yet — relevant once GUI set-management is designed (Decision 6) |
| Q003 | When a user requests custom days for a run's key-day time-course dataset (ADR-009), are those days added to that run's persisted key-day dataset retroactively, or always served as a separate on-demand query, never persisted? | Data | Open | Not yet — relevant once the key-day dataset schema is specified |
| Q004 | Should implementation proceed as one comprehensive change or in incremental, independently-testable phases (Decision 16)? | Migration | **Resolved** — approved as the 8-phase (0-7, 6a/6b) skeleton in `implementation_phases_proposal.md`, with amendments from `implementation_readiness_review.md` incorporated | No longer blocks — Phase 0 authorization is a separate, still-pending step |
| Q005 | What happens to the current override-based Shiny app once migration succeeds? | Migration | **Resolved** — ADR-020: no automatic retirement at any phase gate; formal retirement decided at a dedicated later checkpoint (after Phase 7 walkthrough + Table 162/Sensitivity disposition) | No |
| Q006 | What happens to the current ~581-file static figure batch once the new figure architecture lands? | Reporting | **Resolved** — archived (not deleted) once Phase 6a demonstrates coverage of the batch's primary use cases | No |
| Q007 | Where do Table 162 support and Sensitivity analysis fit in the redesign, given neither appears in any planning document? | Architecture | **Resolved** — ADR-016 (Table 162): deferred, source data preserved through migration, legacy module kept available, dedicated future redesign checkpoint. ADR-017 (Sensitivity): deferred, reconsidered after named-set/run/comparison architecture (Phase 6) is working. Neither is scoped to Phases 0-7 | No |
| Q008 | Should independent adversarial review apply to every implementation ticket, only whole-phase gates, or something else? | Validation | **Resolved** — ADR-019: risk-based, mandatory for 7 named high-risk categories (peak/key-day logic, the evaluation-inputs adapter, migration equivalence, run persistence, aggregation/bound logic, grouped envelopes, multi-run figure traceability); not required for routine GUI/plumbing tickets | No |
| Q009 | Does the migration-equivalence gate need to reference the original assessment source documents (workbooks, Table 162 Word document), not just the extracted `data/reference/*.csv` copies? | Migration, Data | **Resolved** — ADR-018: four-tier provenance model (original source / extracted data / reviewer registers / calculated outputs). Original `.xlsm`/`.docx` files are referenced by verified path + SHA-256 in provenance metadata, never copied into evaluations. All 6 workbook paths and the Table 162 document were independently hash-verified this session (`migration_plan.md` §0.1) | No |
