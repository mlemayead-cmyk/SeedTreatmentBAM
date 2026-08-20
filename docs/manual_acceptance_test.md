# Manual acceptance test

**Purpose.** A structured, numbered pass you can work through yourself,
recording PASS / FAIL / QUESTION for each step. This is more thorough than
`docs/manual_shiny_smoke_test.md` (which is a 15-20 minute first look) and
is meant to be done after that first look, ideally after
`docs/independent_engine_audit.md` is available so you know what is and
isn't independently confirmed yet.

**What this document deliberately excludes.** Per
`docs/word_export_diagnosis.md`, do not download the unfiltered
`risk_and_duration` table or the full quantitative appendix from Word — that
export path is known to hang and is not part of this test.

**How to record results.** Copy the table below into your own notes (or
print it) and fill in the Result and Notes columns as you go. A QUESTION
result is not a failure — it means "I'm not sure this is right, flag it for
the next session."

## Setup

| # | Step | Result | Notes |
|---|---|---|---|
| S1 | Run `Rscript scripts/check_environment.R`. All required packages report `ok`. | | |
| S2 | Run the automated test suite (see `docs/developer_guide.md` for the exact command). All assertions pass, 0 failures. | | |
| S3 | Run `scripts/reviewer_validation_walkthrough.R`. Every row of its final comparison table shows `agrees = TRUE`. | | |
| S4 | Launch the app per `docs/manual_shiny_smoke_test.md` section 1. It reaches `Listening on http://127.0.0.1:8080` within ~10 seconds and the page loads (first load takes ~8-10s; this is normal). | | |

## Part A — Audited baseline scenario (Barley, 300 mg a.i./kg seed, broadcast, small bird)

This scenario has a validated reference: every value below is independently
checkable in `docs/model_walkthrough.md` section 5, and against the audited
workbook cells cited in `docs/scientific_model_specification.md`.

On **Scenario and inputs**: crop group = `small_cereals`, ensure "Barley" is
selected under Crops, "high" under rate levels, "broadcast" under planting
methods, receptors include `bird_small`. Go to **Overview**.

| # | Check | Expected value | Tolerance | Result | Notes |
|---|---|---|---|---|---|
| A1 | Green "no overrides" banner shown | Present | Exact | | |
| A2 | Dose per seed (range shown includes the low/low bound) | 0.00744 mg a.i./seed at the low/low_tkw corner | +/- 0.0001 | | |
| A3 | Initial surface seed (range shown includes the low/low bound) | 180 seeds/m2 at the low/low_tkw broadcast corner | +/- 1 | | |
| A4 | Go to **Official tables**, select "Estimated treated-seed availability and search area". Find the Barley broadcast row. | Surface seed density range should include 180 | +/- 1 | | |
| A5 | Go to **Exposure through time**. Select the Barley/broadcast/low/low scenario, `bird_small`, `bird_acute_screening`. Read day-0 RQ from the "Risk quotient" plot or the "Daily data" table. | RQ approx 1.768 at day 0 | +/- 0.01 | | |
| A6 | Same scenario, `bird_chronic_screening` metric. Day-0 RQ. | RQ approx 9.792 at day 0 (specification cites 9.794 at 3-decimal rounding; `scripts/reviewer_validation_walkthrough.R` computes 9.791973522 and confirms this matches the live engine exactly) | +/- 0.01 | | |
| A7 | "Process separation" plot for this scenario. The combined surface-loading line should visibly fall faster than either the surface-seed line or the residue line alone. | Faster decline, product-of-two-declines shape | Qualitative | | |
| A8 | "Exposure feasibility" tab, same scenario. "Feasibility at sowing" for the Barley broadcast small-bird row. | "Obtainable" | Exact | | |

## Part B — Directional sensitivity (no fixed reference value; direction only)

Use the **Editable assumptions** panel on Scenario and inputs. Change one
thing at a time, return to Overview between steps, and record whether the
direction matches. Click "Reset to assessment defaults" before starting and
between each row unless the step says otherwise.

| # | Change | Expected direction | Result | Notes |
|---|---|---|---|---|
| B1 | Increase Residue dissipation DT50 (e.g. to 40 days) | "Maximum days above metric" increases | | |
| B2 | Decrease Residue dissipation DT50 (e.g. to 5 days) | "Maximum days above metric" decreases | | |
| B3 | Decrease Surface-seed disappearance DT50 (e.g. to 3 days) | Feasibility tab: "Days a full diet is available" decreases | | |
| B4 | Decrease Broadcast surface fraction (e.g. to 0.5) | Overview "Initial surface seed" range decreases for broadcast rows | | |
| B5 | Increase Barley's low TKW substantially (e.g. double it) | "Dose per seed" range increases; RQ at 100% diet is UNCHANGED (dose does not depend on seed mass — section 5 of the walkthrough) | | |
| B6 | Click Reset | Overview numbers return exactly to Part A values; Override register (under Scenario and inputs) shows "No overrides" | | |
| B7 | Run a Sensitivity sweep on "Residue dissipation DT50", response = `peak_rq`. Sweep should show peak_rq is INSENSITIVE to residue DT50 (peak RQ occurs at day 0, before any dissipation) — this is an intentional invariant (specification §9.2: "Dose declines monotonically... so the peak occurs at sowing"). If peak_rq visibly changes across the sweep, that contradicts the specification and should be flagged as a QUESTION. | Flat line | | |
| B8 | Same sweep, response = `days_above_loc`. Should increase with DT50. | Increasing line | | |

## Part C — Edge cases and error handling

| # | Action | Expected | Result | Notes |
|---|---|---|---|---|
| C1 | Set Residue DT50 to 0 in the input box, if the control allows it | The app should show a validation/error message, not a silent NaN or crash — the engine is specified to reject a DT50 of exactly 0 (undefined first-order decay, specification §16) | | |
| C2 | Deselect all dietary fractions (if possible) or all receptors | A graceful message, not a raw R error | | |
| C3 | Select a crop/workbook combination with no data (if reachable through the UI) | A graceful message referencing the missing combination | | |

## Part D — Tables, exports, and the Table 162 view

| # | Action | Expected | Result | Notes |
|---|---|---|---|---|
| D1 | Official tables: view "Estimated treated-seed availability and search area" (186 rows) — safe to view and export | Renders without delay | | |
| D2 | Download that table as CSV | File downloads, opens cleanly, matches the on-screen table | | |
| D3 | Download that table as Word ("This table (Word)") | Completes in well under a minute; renders as a normal table | | |
| D4 | Do **not** attempt Word export of "Risk quotients and duration above the effects metric" (8,928 rows) or the full quantitative appendix — known to hang, see `docs/word_export_diagnosis.md` | N/A — this step is a reminder, not a test | | |
| D5 | Table 162 support tab: pick any decision record | "Peer-review consensus" card explicitly states it is human-controlled and never populated by the software | | |
| D6 | Same tab: confirm "Current recorded position" is labelled `PEER_REVIEW_DECISION, read only` | Present | | |
| D7 | Comparison tab: compare across "crop", facet by "size_class" | Renders a bar chart per crop with no error | | |

## Part E — Provenance and override discipline

| # | Check | Expected | Result | Notes |
|---|---|---|---|---|
| E1 | With one override active (e.g. residue DT50), Overview shows the amber "N override(s) applied" banner, not the green baseline banner | Present | | |
| E2 | Override register table (Scenario and inputs > Override register) lists the override with a `status` of `USER_OVERRIDE` and a non-empty `source` | Present | | |
| E3 | Export the current scenario configuration (download button on Override register), then re-import it after resetting. Confirm the override reappears. | Round-trips correctly | | |
| E4 | Confirm no action in the app has modified any file under `data/reference/` (check file timestamps before/after your session) | Unchanged | | |

## Part F — Maximum obtainable exposure (new feature)

Go to the **Maximum obtainable exposure** tab. Select the Barley/high/
broadcast scenario and `bird_acute_screening` as the effects metric.

| # | Step | Expected behaviour | Reference value | Result | Notes |
|---|---|---|---|---|---|
| F1 | With no overrides applied, read the "Current assumptions" panel | States MSA = 70 m² (short-term), with a one-line explanation citing the source assessment | 70 m2, short-term | | |
| F2 | Read the Summary table's peak values for the small-bird panel | Peak conditional RQ and peak maximum-obtainable RQ are equal | Both ≈ 1.768 (day 0) | | |
| F3 | Read "Day 100% diet unobtainable" for the small-bird panel | A specific day, not "never" | ≈ 83.2 days | | |
| F4 | On the small-bird panel, compare the two curves at a day well before F3's value (e.g. day 30) | The two lines overlap exactly — abundant seed | | | |
| F5 | Compare the two curves at a day well past F3's value (e.g. day 95) | "Maximum obtainable within MSA" is visibly below "100% treated-seed diet" | | | |
| F6 | Open the "Seed availability vs. requirement" companion tab for the small bird | The two lines (availability, requirement) cross at approximately the F3 day | | | |
| F7 | Switch the effects metric to `bird_chronic_screening` | Curves change shape (different metric, same dose/availability); the MSA term shown in "Current assumptions" is unchanged (still short-term — birds always use short-term, acute or chronic) | | | |
| F8 | Go to **Scenario and inputs**, select a mammal scenario/receptor, return to this tab, and pick a mammal **acute** effects metric, then a mammal **chronic** effects metric | The MSA shown in "Current assumptions" changes from 70 m² (short-term) for the acute metric to 35 m² (long-term) for the chronic metric | 70→35 m2 | | |
| F9 | On the small-multiple panel, compare the y-axis ranges across small/medium/large receptor panels | Ranges differ (independent scales); a note below the figure states this explicitly | | | |
| F10 | Apply a residue DT50 override (Scenario and inputs > Editable assumptions), return to this tab | Both curves shift together at every day (both are residue-driven before availability binds); the "Day 100% diet unobtainable" value in the Summary table is **unchanged** (that value depends on surface-seed DT50, not residue DT50) | | | |
| F11 | Reset overrides, apply a surface-seed DT50 override instead | "Day 100% diet unobtainable" changes; the two curves' *early* overlap region is unaffected (residue-driven portion is unchanged) | | | |
| F12 | Apply an MSA override for the receptor currently shown (Scenario and inputs > Editable assumptions has no direct MSA control; use a saved scenario-configuration CSV with an `msa_m2` override if you have one, or skip this step if not) | Only the "Maximum obtainable within MSA" curve moves; "100% treated-seed diet" is unchanged | | | |
| F13 | Change only the effects metric (not dose-affecting inputs) | RQ values change; the Summary table's `day0_seeds_available_within_msa` / seed-availability figures are unchanged | | | |
| F14 | Download the principal figure (PNG). Open it outside the browser/app. | Without looking at Shiny, you can state: crop and treatment rate, receptor body weight, the effects metric and its value, the LOC definition, the initial surface seed density, both DT50 values (labelled so you know which is which), which MSA was used and why, what each curve means, and whether the scenario contains overrides | | | |

## Overall

| Field | Value |
|---|---|
| Tester | |
| Date | |
| Total PASS | |
| Total FAIL | |
| Total QUESTION | |
| Blocking issues found | |

Bring this filled-in sheet to the next session even if everything passed —
a clean run is itself useful evidence to record in `PROJECT_STATE.md`.
