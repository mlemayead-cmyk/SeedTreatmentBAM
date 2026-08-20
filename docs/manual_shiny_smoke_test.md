# Manual Shiny smoke test (first pass, ~15-20 minutes)

**Purpose.** Confirm the dashboard launches and behaves sensibly with your own
eyes, before anything else in this recovery phase proceeds. This is a
qualitative "does it make sense" pass, not a numeric validation. Numeric
validation is a separate document: `docs/manual_acceptance_test.md`, to be
used together with `scripts/reviewer_validation_walkthrough.R`.

Do not treat a number shown here as scientifically confirmed just because the
app displays it consistently. That is what the independent audit
(`docs/independent_engine_audit.md`) is for.

## 1. Launch it

From the project root (`C:\MonDossierMartin\R\seed_treatment_bam_model`), in
a plain PowerShell or R console — RStudio's "Run App" button also works if
you open `app/app.R` in the RStudio project:

```powershell
"C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" scripts\run_app.R
```

This prints:

```
Starting the seed-treatment risk model on http://127.0.0.1:8080
Listening on http://127.0.0.1:8080
```

Open `http://127.0.0.1:8080` in a browser. **The first load takes about
8-10 seconds** (bslib theming plus eight dashboard modules compiling) — this
is normal, not a hang. To use a different port: `Rscript scripts\run_app.R 8090`.

To stop the app, close the console window or press `Ctrl+C` in the terminal
running it.

If it does not start, run `Rscript scripts\check_environment.R` first and
resolve any reported missing packages.

## 2. What you should see on first load

Eight tabs across the top: **Scenario and inputs, Overview, Exposure through
time, Exposure feasibility, Comparison, Official tables, Table 162 support,
Sensitivity.**

You land on **Scenario and inputs**. The sidebar shows "Crop group (source
workbook)" already set to `small_cereals`, with Crops, receptors and effects
metrics pre-populated. A green banner should read *"Assessment baseline. No
overrides applied."* on the Overview tab — check that now.

## 3. The ten changes to make, and what should happen

Do these **in order**, on the **Scenario and inputs** tab unless noted, and
watch the **Overview** tab's four top value boxes (Scenarios modelled,
Maximum field rate, Maximum screening RQ, Maximum days above metric) after
each change. Switch back to Scenario and inputs between steps.

| # | Action | Where | Expected qualitative effect |
|---|---|---|---|
| 1 | Change "Application rate levels" to only `high` | Sidebar | Fewer scenarios modelled; Maximum field rate and Maximum screening RQ should not decrease (you removed only lower rates) |
| 2 | Restore all three rate levels, then change "Effects metric role" to only `REFINED_ADDITIONAL` | Sidebar | Maximum screening RQ box changes (it is now driven by a different, non-screening metric); the RQ number itself will likely be smaller — refined-additional metrics are typically higher toxicity values, but check the box label still says "Maximum screening RQ" even though a refined metric now feeds it, and flag that if it reads as misleading |
| 3 | Restore metric role to `SCREENING`. Open the "Editable assumptions" panel (still on Scenario and inputs) and set **Residue dissipation DT50** to a value *smaller* than the default (try `5`) | Editable assumptions card, "Dissipation" | Overview's "Maximum days above metric" should **decrease** (residue disappears faster, so less time above the effect threshold). The amber override banner should now appear on Overview |
| 4 | Change Residue DT50 to a *larger* value (try `40`) | Same card | "Maximum days above metric" should **increase** relative to the default |
| 5 | Clear Residue DT50 (delete the value, leave blank), set **Surface-seed disappearance DT50** to a small value (try `3`) | Same card | On **Exposure feasibility**, "Days a full diet is available" (Overview box, bottom row) should **decrease** — surface seed disappears faster so less is available for longer |
| 6 | Clear that field. Under "Surface seed by planting method", set **Broadcast surface fraction** to `0.5` (default is 1.0) | Same tab | Overview's "Initial surface seed (seeds/m2)" range should **decrease** for broadcast scenarios (fewer sown seeds end up on the surface) |
| 7 | Clear that field. Pick a crop under "Crop agronomy" → "Crop to edit" (e.g. Barley), and increase **Low thousand-seed weight** noticeably above its default | Same tab | "Dose per seed (mg a.i./seed)" range on Overview should **increase** (heavier seed carries more active ingredient at a fixed mg a.i./kg seed rate); the dose per kg bodyweight (RQ) should **not** change, because a fixed mg/kg-seed rate is dose-independent of seed mass — see specification §9.1. If RQ *does* move when only seed mass changes, that is worth flagging |
| 8 | Clear that field. Click **"Reset to assessment defaults"** | Sidebar | Green "no overrides" banner returns on Overview; all Overview numbers return to their step-1 values; "Override register" tab (under Scenario and inputs) should show "No overrides. Results reflect the assessment baseline." |
| 9 | Go to **Exposure through time**. Pick any scenario/receptor/metric. Look at the **"Process separation"** panel | Exposure through time tab | Three declining curves: surface seeds, residue per seed, and their product (surface loading). The product curve should decline **faster** than either individual curve — this is the two-independent-half-life behaviour described in specification §7.3. Also check the **Dose** and **Risk quotient** panels decline monotonically with no bumps |
| 10 | Go to **Exposure feasibility**. Read the blue banner, then look at the table | Exposure feasibility tab | Banner should explicitly say this is *not* a cap on the regulatory exposure shown elsewhere. In the table, `Feasibility at sowing` should read "Obtainable" for at least the small-bird broadcast rows, consistent with specification §10.1's verified example (small bird, broadcast, ~4,135% of daily diet available at sowing) |

## 4. Quick pass through the remaining tabs

- **Comparison.** Pick "crop" for "Compare across" — you should get one bar
  per crop with no errors.
- **Official tables.** Select each of the four tables in the dropdown; each
  should render without error. Try the CSV download for one table (small,
  fast). **Do not try "This table (Word)" or "All tables (Word)" for
  `risk_and_duration` or the full appendix yet** — see
  `docs/word_export_diagnosis.md` first; a large Word export will hang the
  session.
- **Maximum obtainable exposure.** Select a scenario and the
  `bird_acute_screening` effects metric. Confirm three panels appear
  (small/medium/large bird) each with two lines. Early in the timeframe the
  two lines should overlap exactly; check the "Summary" table's "Day 100%
  diet unobtainable" value — past that day the lines should visibly
  diverge, with "Maximum obtainable within MSA" below "100% treated-seed
  diet". The sidebar's "Current assumptions" should state which MSA (m²)
  and term (short/long) was used, with a one-line explanation citing the
  source assessment.
- **Table 162 support.** Pick a decision record from the dropdown. Confirm
  the "Peer-review consensus" card says the software never populates it, and
  that no field on this tab looks like it is making an acceptability
  decision for you.
- **Sensitivity.** Pick a parameter (e.g. "Residue dissipation DT50"),
  accept the suggested From/To range, click "Run sweep". Confirm the amber
  banner says these are deterministic scenario variants, not an uncertainty
  distribution, and that the resulting line moves in the direction you'd
  expect from step 3/4 above.

## 5. What counts as a failure at this stage

- The app does not start, or the console shows an R error (not just the
  8-10 s startup delay).
- Any tab throws a visible Shiny error ("An error has occurred") rather than
  a graceful `validate()`/`need()` message.
- A directional expectation in section 3 is violated (e.g. increasing
  residue DT50 *decreases* days above the metric).
- The Word or Table 162 warnings are absent, or the peer-review consensus
  field is pre-filled with anything.
- Reset does not fully clear every override (check the Override register
  table, not just the visible fields).

Record anything unexpected verbatim (screenshot if possible) rather than
paraphrasing. Bring it to the next session even if you're not sure it is a
real problem — that is exactly what "REQUIRES_HUMAN_REVIEW" is for in the
independent audit.
