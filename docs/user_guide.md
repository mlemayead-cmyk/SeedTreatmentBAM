# User guide: the Shiny dashboard

This describes what each part of the dashboard does. For a guided,
step-by-step first test, use `docs/manual_shiny_smoke_test.md` instead —
this document is the reference to come back to.

## Starting the application

```powershell
"C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" scripts\run_app.R
```

Then open `http://127.0.0.1:8080`. First load takes about 8-10 seconds.
Use `scripts\run_app.R 8090` (or any port number) if 8080 is in use. Stop
the app by closing its console window.

## The eight tabs

### Scenario and inputs

This is where you choose what to look at and, optionally, change an
assumption. It has a sidebar and three sub-tabs.

**Sidebar — what to model:**

- **Crop group (source workbook).** Which audited calculation workbook's
  crops to draw from (e.g. `small_cereals`). Only crops with an actual
  registered application rate in `scenario_definitions.csv` can be
  modelled — see `docs/data_dictionary.md` for which crop groups currently
  have this.
- **Crops, Application rate levels, Planting methods, Receptors, Effects
  metric role, Dietary fractions.** Filters. Leaving everything selected
  models every combination; narrowing these speeds up the dashboard and
  produces smaller exports.
- **Maximum search area.** Short-term (1 day) or long-term (21 day) MSA —
  affects only the Exposure feasibility tab and the feasibility columns
  elsewhere; never the calculated dose or RQ (specification §10.3).
- **Simulation length (days).** How far the "Exposure through time" plots
  extend.
- **Reset to assessment defaults.** Clears every override below. Never
  modifies the underlying `data/reference/*.csv` files — resetting is
  always safe and always recoverable.

**Sub-tab: Editable assumptions.** Change dissipation half-lives, surface
seed fractions by planting method, or one crop's thousand-seed weight /
seeding rate bounds. Leave a field blank to keep the assessment default.
Every change is an **override**, held in a separate layer from the
baseline — it never edits `data/reference/*.csv`. The "Effect of the
current overrides" table at the bottom shows baseline vs. current for eight
key summary quantities, so a change's consequence is visible immediately
rather than hidden in a plot you have to go find.

**Dissipation-half-life overrides apply globally, to every crop at once —
this is by design, not a bug.** The two "Dissipation" fields (surface-seed
and residue DT50) are the only controls in this panel scoped `"global"`
rather than to one crop or method. Overriding either one changes that
half-life for every scenario currently displayed, immediately. This was
specifically checked in the independent audit (finding AUD-093): a
global-scope override is not accidentally narrow, and there is currently no
in-app warning beyond this note, so double-check your crop/scenario
selection before reading results after changing either dissipation field.

**Sub-tab: Override register.** Every active override, with its scope,
baseline value, new value, status, and source. Export the current scenario
(a small CSV of just the overrides — the baseline itself is never
duplicated into scenario files) and reload it in a later session.

**Sub-tab: Assessment defaults.** Read-only view of the immutable baseline:
receptor parameters, planting-method surface fractions, effects metrics,
and source workbook provenance (with SHA-256 hashes).

### Overview

Eight value boxes summarising the current selection: scenarios modelled,
maximum field rate, maximum screening RQ, maximum days above the metric,
initial surface seed range, dose-per-seed range, the dietary fraction at
which the metric is exactly reached, and the number of days a full diet
remains available. A banner at the top states plainly whether you are
looking at the assessment baseline or a scenario with overrides applied —
check this before reading any other number on the page.

Below the value boxes: the full `scenario_inputs` table for the current
selection, filterable and sortable.

### Exposure through time

Pick one scenario, one receptor, one effects metric. Six plots (surface
seed, residue per seed, surface loading, dose, risk quotient, and a
"process separation" view showing all three declining quantities together)
plus a data table and CSV/PNG export. The "process separation" plot is the
most important one to look at when first understanding a scenario — it
shows visually that surface-seed loss and residue dissipation are different
processes with different speeds (`docs/model_walkthrough.md` section 6).

### Maximum obtainable exposure

Answers a sharper question than "Exposure through time": not just what the
dose/RQ would be at an assumed dietary fraction, but the **largest dose
this receptor could actually get**, given how much treated seed genuinely
remains and without exceeding its own food requirement. Pick one scenario
and one effects metric; the tab shows a small-multiple panel, one per
receptor size of the metric's taxon (small/medium/large), each with two
lines: "100% treated-seed diet" (the conventional conditional RQ) and
"Maximum obtainable within MSA" (capped at the lesser of the food
requirement and the seed actually available). The two lines are identical
while seed is abundant and diverge once availability becomes the binding
constraint — the point of divergence is itself informative.

Panels use independent y-axis scales by default (a 20 g and a 1000 g
receptor rarely share a sensible RQ range) — this is stated explicitly in
the figure, never left implicit. The sidebar's "Current assumptions" panel
shows the scenario, treatment, both DT50 values, the effects metric, and —
critically — which maximum search area (MSA) was used and why: this tab
resolves the correct MSA automatically from the source assessment's own
policy (birds always short-term; mammals short-term for acute and
long-term for chronic/reproductive characterization — assessment paragraph
`MAIN-P000209`) rather than exposing it as a manual toggle, unlike the
"Exposure feasibility" tab's general-purpose diagnostic.

A "Summary" table gives peak RQs and the exact day each curve crosses the
level of concern, plus the day 100%/50%/25% of the assumed diet stops being
obtainable. Companion tabs below show why: seed availability against
requirement, and the underlying surface-seed/residue/surface-loading
processes (the same plots as "Exposure through time"). The downloaded
figure (PNG or SVG) carries its own title, legend and a full assumptions
footnote — it does not require this Shiny page to be interpreted correctly,
which makes it suitable for direct use in a Word report.

### Exposure feasibility

A blue banner reiterates that this tab is a plausibility diagnostic, not an
exposure cap. Two plots (search area required vs. maximum available;
maximum obtainable dietary fraction) and a table answering, for every
scenario/receptor combination, "Obtainable" / "Obtainable for some bounds"
/ "Not obtainable".

### Comparison

Bar charts of peak RQ or duration-above-metric, grouped and faceted however
you choose (by crop, rate level, planting method, size class, or receptor).
Useful for seeing which crop/rate combinations are furthest from or closest
to a level of concern, without leaving the dashboard.

### Official tables

The four tables the model can produce in a form matching the source
assessment's table layouts (see `STBAM_TABLES` in
`R/reporting/31_tables.R`). Select one, optionally add a caption prefix
(e.g. "Table 27."), and export as Word (single table, all four tables, or
the full quantitative appendix) or CSV. **Do not export "Risk quotients and
duration above the effects metric" or the full appendix to Word without
first narrowing your Crop selection** — see `docs/word_export_diagnosis.md`
for why an unfiltered export of that table hangs.

### Table 162 support

A red banner states plainly that the application does not make the
scientific decision. Pick a decision record to see its quantitative
backbone (screening RQ, days above metric, maximum obtainable diet) next to
the source assessment's factors increasing/decreasing concern, contextual
evidence, uncertainty, and current narrative reasoning — each explicitly
labelled by provenance class (`CALCULATED`, `SOURCE_EVIDENCE`,
`REVIEWER_INTERPRETATION`). The peer-review consensus field is always
empty and always will be; it is recorded outside the application.

The "Coverage" table at the top shows which crop families have no supplied
calculation workbook — these are reported, not hidden, consistent with
`docs/table162_support_methodology.md`.

### Sensitivity

Vary one parameter (thousand-seed weight, seeding rate, surface-seed
fraction, either dissipation half-life, or MSA) over a range you choose,
and see the effect on a response you choose (peak RQ, days above the
metric, surface seed density, field rate, maximum obtainable diet, days a
full diet is available, or required search area). An amber banner states
these are deterministic one-at-a-time scenario variants, not a probability
distribution — do not read a sensitivity sweep as an uncertainty range.

## Interpreting RQ direction

An RQ at or above 1 means modelled exposure reaches or exceeds the effects
metric used. Screening metrics already include an uncertainty factor;
refined/refined-additional metrics generally do not (see
`data/reference/effects_metrics.csv`, column `uncertainty_factor`) — do not
compare a screening RQ and a refined RQ as if they were on the same scale
without checking which metric role produced each one.

## Baseline vs. override, at a glance

| | Where it lives | Can be reset | Ever written to `data/reference/`? |
|---|---|---|---|
| Assessment baseline | `data/reference/*.csv` | N/A (it is the reset target) | No — read-only |
| Your overrides | In-memory, this session only | Yes, via "Reset to assessment defaults" | Never |
| Exported scenario config | A CSV you download | You choose when to reload it | No |

Closing the browser tab or stopping the R process discards any unsaved
overrides. Export the scenario configuration first if you want to keep it.
