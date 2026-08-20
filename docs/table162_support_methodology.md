# Table 162 support: methodology

## What Table 162 is

In the source assessment, Table 162 is the summary table where every
crop/rate/planting-method x receptor/effect combination gets a provisional
acceptability position (Y/N/? or not yet populated). The source review
project (`03_registers/table162_decision_matrix.csv`,
`table162_considerations.csv`) already built a structured, traceable
inventory of every one of those decision cells and the evidence bearing on
each — that work is not repeated here, only **connected** to this model's
quantitative output.

## What this model adds, and what it deliberately does not do

`build_table162_support()` (`R/summaries/24_table162_support.R`) joins two
things that previously lived in separate projects:

1. The **decision matrix and consideration register** (evidence,
   uncertainty, current narrative reasoning, current recorded position) —
   copied read-only from the review project, unchanged.
2. This model's own **calculated quantitative backbone** (screening RQ,
   duration above the metric, surface seed availability, exposure
   feasibility) — computed fresh from the current parameter set, so it
   updates immediately if you change an assumption in the dashboard.

**It does not decide anything.** `current_table162_position` is copied
through read-only, labelled `PEER_REVIEW_DECISION`. Two fields —
`peer_review_consensus` and `consensus_rationale` — are created **empty on
every row** and no code path anywhere writes to them
(`STBAM_HUMAN_ONLY_FIELDS`, enforced by `assert_human_fields_empty()`,
which is called by the test suite and before every export — if you ever see
this assertion fail, treat it as a serious defect, not a warning).

## How the join works

The decision matrix is keyed by **crop family** (e.g. "Small Cereals",
"Legumes"), not by individual crop — because the published assessment
groups crops that way. `build_table162_backbone()` first maps this model's
`workbook` values onto the same crop-family labels
(`STBAM_WORKBOOK_TO_CROP_FAMILY`), and maps this model's planting-method
codes onto the register's several spellings for the same method
(`STBAM_METHOD_TO_REGISTER` — e.g. `drill_spring` matches "Spring drill",
"Standard drill (spring)", or "Standard drilling", whichever the register
happens to use for that row). The join key is then crop family x planting
method x taxon x receptor size x effect window x rate value x rate unit.

**A crop family can have several model crops feeding one decision row**
(e.g. several individual Small Cereals crops all rolling up to one "Small
Cereals" decision). `quantitative_backbone_available` and the coverage
report below both count this correctly — they are never inflated by
counting rows instead of distinct decisions.

## The coverage report: showing gaps, not hiding them

`table162_coverage()` reports, per crop family, how many decision rows have
a quantitative backbone and how many do not — for example, a crop family
the review project flagged as structurally incomplete
(mammalian Legumes, mammalian Cucurbits, mammalian Sunflower — see the
source review project's Phase 4A inventory) will show up here with
`without_quantitative_backbone > 0`, not silently disappear from the
dashboard. This is deliberate: a missing quantitative backbone is
information a reviewer needs, not noise to be filtered out.

## Provenance classes on every field

| Field group | Class | Meaning |
|---|---|---|
| `current_table162_position` | `PEER_REVIEW_DECISION` | Copied read-only from the register; this model never sets it |
| `screening_rq_max`, `days_above_loc_max`, `field_rate_g_ai_per_ha_max`, `max_feasible_diet_pct`, etc. | `CALCULATED` | Computed fresh from the current parameter set |
| `factors_increasing_concern`, `factors_decreasing_concern`, `contextual_evidence` | `SOURCE_EVIDENCE` | Taken from the review project's consideration register, direction-separated (`INCREASES_CONCERN` / `DECREASES_CONCERN` / other) |
| `current_narrative_reasoning` | `REVIEWER_INTERPRETATION` | The review project's own reading of the assessment's stated rationale — not this model's interpretation |
| `peer_review_consensus`, `consensus_rationale` | (human only) | Always `NA`; never written by software |

## Using this in the dashboard

The "Table 162 support" tab presents one decision record at a time with
these fields grouped visually the same way — quantitative value boxes,
then evidence-by-direction cards, then the human-only consensus card
explicitly labelled as such. See `docs/user_guide.md` for the tab
walkthrough.

## Limitations

- The quantitative backbone is only as complete as the underlying crop
  coverage — see `docs/data_dictionary.md` for which 6 crop groups
  currently have registered application rates, and
  `docs/independent_engine_audit.md` / `PROJECT_STATE.md` for which of
  those are independently numerically audited versus scenario-source only.
- The crop-family and planting-method mapping tables
  (`STBAM_WORKBOOK_TO_CROP_FAMILY`, `STBAM_METHOD_TO_REGISTER`) are
  maintained by hand in `R/summaries/24_table162_support.R`. If a new
  workbook or planting-method spelling is added to either side, this
  mapping needs a corresponding update or the join will silently produce
  `quantitative_backbone_available = FALSE` for that row instead of an
  error — this is a designed fail-open-to-"gap-reported", not a
  fail-loud, and is worth keeping in mind if a row you expect to have a
  backbone doesn't.
- `metric_role` defaults to `SCREENING` — refined/refined-additional
  metrics are available in `scenario_summary` but are not the default
  backbone metric for this join; pass a different `metric_role` to
  `build_table162_support()` if a refined-metric backbone is wanted.
