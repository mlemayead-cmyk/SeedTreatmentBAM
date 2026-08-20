#!/usr/bin/env Rscript
# ============================================================================
# REVIEWER VALIDATION WALKTHROUGH
# ============================================================================
#
# Who this is for: you, the scientific reviewer, not an R programmer.
#
# What this script is NOT: it is not the automated test suite
# (tests/testthat/), and it is not the independent adversarial audit
# (docs/independent_engine_audit.md). Both of those exist separately.
#
# What this script IS: a single, heavily-commented worked example that
# calculates one real scenario from raw numbers, by hand, in plain R
# arithmetic -- the same way you might work through it on a calculator or in
# a spreadsheet. It does NOT call the model's own R functions until Part 17,
# where it loads the actual engine and shows you, side by side, whether the
# engine agrees with the by-hand calculation above it.
#
# The point is that you should be able to read every line between here and
# Part 17 and follow the arithmetic yourself, without needing to trust any
# R function you haven't seen the inside of.
#
# Run it with:
#   "C:\Program Files\R\R-4.4.3\bin\x64\Rscript.exe" scripts\reviewer_validation_walkthrough.R
# from the project root. It prints its work as it goes and finishes with a
# comparison table.
#
# The worked scenario: BARLEY, 300 mg a.i./kg seed, BROADCAST planting,
# SMALL BIRD (20 g), against both the acute and chronic screening effects
# metrics. This is the same scenario cited repeatedly in
# docs/scientific_model_specification.md, so every intermediate number below
# can also be checked against that document's "Verified" citations to the
# audited source workbook.
# ============================================================================

cat("============================================================\n")
cat("REVIEWER VALIDATION WALKTHROUGH\n")
cat("Scenario: Barley, 300 mg a.i./kg seed, broadcast, small bird\n")
cat("============================================================\n\n")

# ----------------------------------------------------------------------------
# PART 1. Define crop and treatment inputs
# ----------------------------------------------------------------------------
# These are raw numbers taken directly from data/reference/crop_seeding_
# parameters.csv (Barley row) and data/reference/scenario_definitions.csv
# (Barley, rate_level = "high"). They are read here as plain literals so this
# script does not depend on the CSV-reading code being correct -- you can
# open those two CSV files yourself and check these eight numbers by eye.

application_rate_mg_per_kg_seed <- 300      # registered seed-treatment rate
tkw_low_g_per_1000  <- 24.8                 # low-bound thousand-seed weight
tkw_high_g_per_1000 <- 59.5                 # high-bound thousand-seed weight
seeds_per_ha_low   <- 1800000               # low-bound seeding rate, DIRECT
seeds_per_ha_high  <- 4700000               # high-bound seeding rate, DIRECT
surface_seed_fraction_broadcast <- 1.0      # planting_method_parameters.csv

cat("Part 1. Inputs (from data/reference/*.csv, read by eye, not by code)\n")
cat(sprintf("  Application rate:        %g mg a.i./kg seed\n",
            application_rate_mg_per_kg_seed))
cat(sprintf("  TKW low / high:           %g / %g g per 1000 seeds\n",
            tkw_low_g_per_1000, tkw_high_g_per_1000))
cat(sprintf("  Seeds/ha low / high:      %s / %s\n",
            format(seeds_per_ha_low, big.mark = ","),
            format(seeds_per_ha_high, big.mark = ",")))
cat(sprintf("  Broadcast surface fraction: %g\n\n", surface_seed_fraction_broadcast))

# We work the LOW bound (low seeds/ha) with the LOW TKW throughout this
# script, i.e. the "low / low_tkw" corner of the 2x2 agronomic grid described
# in specification section 4.1. This corner is directly checkable against the
# workbook cells the specification cites (Seed Inputs and EECs!F4, Q4, W4,
# AC4, AK4).

# ----------------------------------------------------------------------------
# PART 2. Seed mass from thousand-seed weight
# ----------------------------------------------------------------------------
# TKW is grams per 1000 seeds, so one seed weighs TKW / 1000 grams.

seed_mass_g <- tkw_low_g_per_1000 / 1000

cat("Part 2. Seed mass\n")
cat(sprintf("  seed_mass_g = %g / 1000 = %.6f g/seed\n\n",
            tkw_low_g_per_1000, seed_mass_g))

# ----------------------------------------------------------------------------
# PART 3. Seeds per hectare
# ----------------------------------------------------------------------------
# Barley's low-bound seeding rate is stored DIRECTLY as a seed count
# (1,800,000 seeds/ha), not derived from a mass rate. So this step is a
# lookup, not a calculation -- but it matters that you can see WHY there is
# no arithmetic here for this particular crop: some crops in
# crop_seeding_parameters.csv give a mass rate instead, and for those the
# model derives seeds/ha as  seeding_rate_kg_per_ha * 1e6 / TKW_g_per_1000
# (specification section 5.2). Barley just happens to skip that step because
# the workbook already gives a seed count.

seeds_per_ha <- seeds_per_ha_low

cat("Part 3. Seeds per hectare\n")
cat("  Barley's low-bound rate is a DIRECT seed count in the source data,\n")
cat(sprintf("  so seeds_per_ha = %s (no conversion needed for this crop)\n\n",
            format(seeds_per_ha, big.mark = ",")))

# ----------------------------------------------------------------------------
# PART 4. Seeds per square metre
# ----------------------------------------------------------------------------
# 1 hectare = 10,000 m^2.

seeds_per_m2 <- seeds_per_ha / 10000

cat("Part 4. Seeds per square metre\n")
cat(sprintf("  seeds_per_m2 = %s / 10,000 = %g seeds/m2\n\n",
            format(seeds_per_ha, big.mark = ","), seeds_per_m2))

# ----------------------------------------------------------------------------
# PART 5. Surface seed density
# ----------------------------------------------------------------------------
# Not every sown seed ends up visible on the soil surface where a bird or
# mammal can find it. The proportion that does depends on planting method
# (de Snoo & Luttik 2004, as cited in planting_method_parameters.csv).
# Broadcast seeding leaves essentially everything on the surface
# (fraction = 1.0); drilling buries most of it (fraction 0.033-0.092).

initial_surface_seeds_per_m2 <- seeds_per_m2 * surface_seed_fraction_broadcast

cat("Part 5. Surface seed density (broadcast)\n")
cat(sprintf("  surface_seeds_m2 = %g seeds/m2 x %g (broadcast fraction) = %g seeds/m2\n",
            seeds_per_m2, surface_seed_fraction_broadcast,
            initial_surface_seeds_per_m2))
cat("  Cross-check: specification section 6 cites the audited workbook cell\n")
cat("  'Seed Inputs and EECs!AC4' as 180 seeds/m2 for this exact scenario.\n\n")

# ----------------------------------------------------------------------------
# PART 6. Active ingredient per seed
# ----------------------------------------------------------------------------
# The registered rate here is in mg a.i. PER KG of seed. To get mg a.i. on
# ONE seed, multiply by that seed's mass in kg (seed_mass_g / 1000).

dose_per_seed_mg <- application_rate_mg_per_kg_seed * (seed_mass_g / 1000)

cat("Part 6. Active ingredient (a.i.) per seed\n")
cat(sprintf("  dose_per_seed_mg = %g mg/kg x (%.6f g / 1000) = %.6f mg a.i./seed\n",
            application_rate_mg_per_kg_seed, seed_mass_g, dose_per_seed_mg))
cat("  Cross-check: specification section 5.3 cites workbook cell 'Q4' as\n")
cat("  0.00744 mg a.i./seed for barley at 300 mg/kg with TKW 24.8.\n\n")

# ----------------------------------------------------------------------------
# PART 7. Active ingredient applied to the field (g a.i./ha)
# ----------------------------------------------------------------------------
# This uses the MASS seeding rate, not the seed count. Barley's low-bound
# mass rate at the low TKW is 44.64 kg seed/ha (workbook cell F4). The field
# loading is: (mg a.i./kg seed / 1000) x kg seed/ha = g a.i./ha.

seeding_rate_kg_per_ha_low_low_tkw <- 44.64   # workbook 'Seed Inputs and EECs!F4'

field_rate_g_ai_per_ha <- (application_rate_mg_per_kg_seed / 1000) *
  seeding_rate_kg_per_ha_low_low_tkw

cat("Part 7. Active ingredient applied to the field\n")
cat(sprintf("  field_rate_g_ai_per_ha = (%g / 1000) x %g kg/ha = %.4f g a.i./ha\n",
            application_rate_mg_per_kg_seed, seeding_rate_kg_per_ha_low_low_tkw,
            field_rate_g_ai_per_ha))
cat("  Cross-check: specification section 5.4 cites workbook cell 'W4' as\n")
cat("  13.392 g a.i./ha for this exact scenario.\n\n")

# ----------------------------------------------------------------------------
# PART 8. Define the receptor (small bird)
# ----------------------------------------------------------------------------
# From data/reference/receptor_parameters.csv, row bird_small. The food
# ingestion rate (FIR) is a Nagy (1987) allometric regression:
#     FIR = a * BW^b        (grams dry-weight diet per day)
# This is a DRY-WEIGHT figure. No dry-to-fresh conversion is applied,
# because none is specified anywhere in the source assessment or workbook
# (specification section 8, and the stated limitation in section 14).

body_weight_g   <- 20.0
fir_coefficient_a <- 0.398
fir_exponent_b    <- 0.85

cat("Part 8. Receptor: small bird\n")
cat(sprintf("  body_weight_g = %g g\n", body_weight_g))
cat(sprintf("  FIR regression: 'Nagy 1987, Passerines', a = %g, b = %g\n\n",
            fir_coefficient_a, fir_exponent_b))

# ----------------------------------------------------------------------------
# PART 9. Daily food requirement
# ----------------------------------------------------------------------------

food_intake_g_dw_per_day <- fir_coefficient_a * body_weight_g ^ fir_exponent_b

cat("Part 9. Daily food requirement (dry-weight diet)\n")
cat(sprintf("  FIR = %g x %g^%g = %.9f g dry-weight diet/day\n",
            fir_coefficient_a, body_weight_g, fir_exponent_b,
            food_intake_g_dw_per_day))
cat("  Cross-check: data/reference/receptor_parameters.csv stores\n")
cat("  5.078770266809547 for bird_small; this should match to the digit.\n\n")

# ----------------------------------------------------------------------------
# PART 10. Number of seeds required per day, at a given dietary fraction
# ----------------------------------------------------------------------------
# "Required" is what the animal NEEDS to meet that fraction of its diet as
# treated seed -- not what is physically available. Availability is a
# separate question, handled in Part 16.

diet_fraction_full <- 1.00   # 100% of the diet as treated seed (screening)

seeds_required_per_day_full_diet <- (food_intake_g_dw_per_day / seed_mass_g) *
  diet_fraction_full

cat("Part 10. Seeds required per day (100% treated-seed diet)\n")
cat(sprintf("  seeds_required = (%.6f g/d / %.6f g/seed) x %g = %.4f seeds/day\n",
            food_intake_g_dw_per_day, seed_mass_g, diet_fraction_full,
            seeds_required_per_day_full_diet))
cat("  (This is what a 20 g bird eating only barley seed would need to eat\n")
cat("  to get its full daily ration; it says nothing yet about whether that\n")
cat("  many seeds are actually available on the ground -- see Part 16.)\n\n")

# ----------------------------------------------------------------------------
# PART 11. Daily dose (Estimated Daily Exposure, EDE)
# ----------------------------------------------------------------------------
# Two independent ways to arrive at the same number (specification section
# 9.1). Both are computed here and must agree with each other before we even
# get to the engine comparison in Part 17.
#
# Method A (concentration form):
#   EDE = C_seed [mg/kg seed] x FIR [g/d] / BW [g] x diet_fraction
#   The g/g ratio (FIR/BW) is dimensionless, so mg/kg seed carries straight
#   through to mg/kg bw/day with no extra numeric factor.
#
# Method B (per-seed form):
#   EDE = seeds_consumed_per_day x dose_per_seed_mg / (BW_g / 1000)

ede_A_concentration_form <- application_rate_mg_per_kg_seed *
  food_intake_g_dw_per_day / body_weight_g * diet_fraction_full

ede_B_per_seed_form <- seeds_required_per_day_full_diet * dose_per_seed_mg /
  (body_weight_g / 1000)

cat("Part 11. Daily dose (EDE), two independent methods\n")
cat(sprintf("  Method A (concentration form): %.6f mg a.i./kg bw/day\n",
            ede_A_concentration_form))
cat(sprintf("  Method B (per-seed form):      %.6f mg a.i./kg bw/day\n",
            ede_B_per_seed_form))
cat(sprintf("  Difference: %.2e (should be at or near machine precision)\n",
            abs(ede_A_concentration_form - ede_B_per_seed_form)))
cat("  Cross-check: specification section 9.1 cites 76.1816 mg a.i./kg bw/d\n")
cat("  for this exact scenario.\n\n")

ede_full_diet <- ede_A_concentration_form   # use for the rest of the script

# ----------------------------------------------------------------------------
# PART 12. Risk quotient (RQ)
# ----------------------------------------------------------------------------
# RQ = dose / effects metric. Screening effects metrics, from
# data/reference/effects_metrics.csv:
#   bird_acute_screening   = 43.1  mg a.i./kg bw/d  (Canary, UF 10)
#   bird_chronic_screening = 7.78  mg a.i./kg bw/d  (Northern bobwhite NOEL)

bird_acute_screening_metric   <- 43.1
bird_chronic_screening_metric <- 7.78

rq_acute   <- ede_full_diet / bird_acute_screening_metric
rq_chronic <- ede_full_diet / bird_chronic_screening_metric

cat("Part 12. Risk quotient at the screening metrics\n")
cat(sprintf("  RQ (acute)   = %.6f / %.4f = %.4f\n",
            ede_full_diet, bird_acute_screening_metric, rq_acute))
cat(sprintf("  RQ (chronic) = %.6f / %.4f = %.4f\n",
            ede_full_diet, bird_chronic_screening_metric, rq_chronic))
cat("  Cross-check: specification section 9.3 cites acute RQ 1.768 and\n")
cat("  chronic RQ 9.794 for this exact scenario.\n\n")

# ----------------------------------------------------------------------------
# PART 13. Seed disappearance from the soil surface, over time
# ----------------------------------------------------------------------------
# Surface seed is lost over time to displacement, burial, germination and
# predation -- NOT to pesticide breakdown. This is modelled as a first-order
# process with its own half-life (DT50 = 14 days, from
# data/reference/dissipation_parameters.csv):
#   S(t) = S(0) * 2^(-t / DT50)
# THIS IS A DIFFERENT PROCESS from Part 14. Do not confuse the two -- mixing
# them up is exactly the kind of error the specification warns about in
# section 7.

surface_seed_dt50_days <- 14.0

surface_seeds_over_time <- function(t) {
  initial_surface_seeds_per_m2 * 2 ^ (-t / surface_seed_dt50_days)
}

cat("Part 13. Surface-seed disappearance (NOT residue dissipation)\n")
cat(sprintf("  DT50 = %g days. S(t) = S(0) x 2^(-t / %g)\n", surface_seed_dt50_days,
            surface_seed_dt50_days))
for (t in c(0, 7, 14, 28, 60)) {
  cat(sprintf("    day %2d: %8.3f seeds/m2\n", t, surface_seeds_over_time(t)))
}
cat("  Sanity check: the day-14 value should be exactly half the day-0 value,\n")
cat("  because day 14 IS the half-life.\n\n")

# ----------------------------------------------------------------------------
# PART 14. Residue dissipation per seed, over time
# ----------------------------------------------------------------------------
# The active ingredient carried by a seed that is STILL PRESENT declines
# separately, with its own half-life (DT50 = 10 days). This is a different
# number from Part 13's half-life, and the two processes are never allowed
# to share a parameter anywhere in the engine.

residue_dt50_days <- 10.0

ai_per_seed_over_time <- function(t) {
  dose_per_seed_mg * 2 ^ (-t / residue_dt50_days)
}

cat("Part 14. Residue dissipation per seed (NOT surface-seed loss)\n")
cat(sprintf("  DT50 = %g days. A(t) = A(0) x 2^(-t / %g)\n", residue_dt50_days,
            residue_dt50_days))
for (t in c(0, 5, 10, 20, 40)) {
  cat(sprintf("    day %2d: %.6f mg a.i./seed\n", t, ai_per_seed_over_time(t)))
}
cat("\n")

# ----------------------------------------------------------------------------
# PART 15. Dose and risk quotient through time
# ----------------------------------------------------------------------------
# The dose an animal receives declines with RESIDUE dissipation only
# (Part 14's half-life). Whether enough surface seed remains to physically
# obtain that dose is a SEPARATE feasibility question (Part 16) and is
# deliberately NOT applied as a cap here (specification section 10.3) --
# this is one of the most important design decisions in the whole model, and
# worth checking carefully.
#
# Also computed here: the combined active-ingredient loading on the soil
# surface, which multiplies BOTH declining processes together and therefore
# falls faster than either one alone (specification section 7.3).

dose_over_time <- function(t) ede_full_diet * 2 ^ (-t / residue_dt50_days)
rq_over_time   <- function(t) dose_over_time(t) / bird_chronic_screening_metric
surface_loading_over_time <- function(t) {
  surface_seeds_over_time(t) * ai_per_seed_over_time(t)
}

cat("Part 15. Dose, RQ (chronic) and combined surface loading through time\n")
cat(sprintf("%6s %14s %10s %20s\n", "day", "dose", "RQ", "surface loading"))
for (t in c(0, 7, 14, 21, 28)) {
  cat(sprintf("%6d %14.6f %10.4f %20.6f\n", t, dose_over_time(t), rq_over_time(t),
              surface_loading_over_time(t)))
}
cat("  Check: the surface-loading column should fall FASTER than either the\n")
cat("  surface-seed column (Part 13) or the residue-per-seed column (Part 14)\n")
cat("  taken alone, because it is the product of both declines at once.\n\n")

# Duration above the chronic screening metric: solve dose(t) = metric for t.
# dose(t) = ede * 2^(-t/DT50)  =>  t = DT50 * log2(ede / metric)
days_above_chronic_metric <- residue_dt50_days *
  log2(ede_full_diet / bird_chronic_screening_metric)

cat(sprintf("  Days at or above the chronic screening metric: %.4f days\n",
            days_above_chronic_metric))
cat("  Cross-check: specification section 9.4 cites 27.0664 days for small\n")
cat("  bird at 200 mg/kg chronic (a different rate than this walkthrough's\n")
cat("  300 mg/kg, so do not expect an exact match -- only the same order and\n")
cat("  the same formula shape).\n\n")

# ----------------------------------------------------------------------------
# PART 16. Maximum search area (MSA) diagnostics
# ----------------------------------------------------------------------------
# This section answers "could the bird realistically FIND this many treated
# seeds?" -- a plausibility check, separate from the regulatory dose/RQ
# above. From receptor_parameters.csv, small bird short-term MSA = 70 m2.

msa_m2 <- 70.0

available_seeds_within_msa <- initial_surface_seeds_per_m2 * msa_m2
seeds_for_full_diet <- food_intake_g_dw_per_day / seed_mass_g
max_feasible_diet_fraction <- available_seeds_within_msa / seeds_for_full_diet
required_search_area_m2 <- seeds_required_per_day_full_diet /
  initial_surface_seeds_per_m2

cat("Part 16. Exposure feasibility (MSA diagnostic, NOT an exposure cap)\n")
cat(sprintf("  Seeds available within a %g m2 search area: %.2f seeds\n",
            msa_m2, available_seeds_within_msa))
cat(sprintf("  Maximum feasible dietary fraction: %.2f (i.e. %.1f%% of a full diet)\n",
            max_feasible_diet_fraction, max_feasible_diet_fraction * 100))
cat(sprintf("  Search area required for a full diet: %.4f m2 (well under the %g m2 MSA)\n",
            required_search_area_m2, msa_m2))
cat("  Cross-check: specification section 10.1 cites 4200 seeds available\n")
cat("  and 4134.86%% of daily diet for the wheat-lower-broadcast small-bird\n")
cat("  case; the shape of the calculation is the same, the crop differs.\n")
cat("  IMPORTANT: nothing calculated in this Part 16 has been allowed to\n")
cat("  change the dose or RQ figures computed in Parts 11-12 or 15. That\n")
cat("  separation is deliberate -- see specification section 10.3.\n\n")

# ============================================================================
# PART 17. Compare every number above with the actual R engine
# ============================================================================
# Everything above this line used only base R arithmetic on numbers you can
# read directly out of the CSV files. Now, and only now, we load the real
# engine and ask it for the same scenario, so you can see whether it agrees.
#
# IMPORTANT HOUSEKEEPING: the engine exports functions with names such as
# seeds_per_m2() and field_rate_g_ai_per_ha() -- the SAME names this script
# used above for plain hand-calculated NUMBERS. Loading the engine into this
# same R session would silently overwrite those numbers with functions. That
# is exactly the kind of hidden-coupling mistake a careful reviewer should
# watch for, so rather than quietly avoid it, we snapshot every
# hand-calculated number into a clearly separate `hand` list FIRST, and use
# only `hand$...` from this point on.

hand <- list(
  seed_mass_g = seed_mass_g,
  seeds_per_ha = seeds_per_ha,
  seeds_per_m2 = seeds_per_m2,
  initial_surface_seeds_per_m2 = initial_surface_seeds_per_m2,
  dose_per_seed_mg = dose_per_seed_mg,
  field_rate_g_ai_per_ha = field_rate_g_ai_per_ha,
  food_intake_g_dw_per_day = food_intake_g_dw_per_day,
  seeds_required_per_day_full_diet = seeds_required_per_day_full_diet,
  ede_full_diet = ede_full_diet,
  rq_acute = rq_acute,
  rq_chronic = rq_chronic
)

cat("============================================================\n")
cat("Part 17. Loading the actual R engine for comparison\n")
cat("============================================================\n\n")

root <- getwd()
if (!dir.exists(file.path(root, "R"))) {
  stop("Run this script from the project root: ",
       "C:\\MonDossierMartin\\R\\seed_treatment_bam_model", call. = FALSE)
}
source(file.path(root, "R", "load_model.R"))
load_stbam(root, include = c("core", "reporting"))

baseline <- load_baseline()
params <- parameter_set(baseline, "Reviewer walkthrough (assessment baseline)")
stopifnot(!has_overrides(params))   # confirms no override contaminates this run

engine_inputs <- build_scenario_inputs(
  params, crops = "Barley", workbooks = "small_cereals", rate_levels = "high",
  planting_methods = "broadcast"
)
engine_row <- engine_inputs[
  engine_inputs$seeding_rate_bound == "low" &
    engine_inputs$seed_mass_bound == "low_tkw",
]
stopifnot(nrow(engine_row) == 1L)

receptors <- resolve_receptors(params, receptors = "bird_small")
metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "bird")
engine_summary <- build_scenario_summary(params, engine_row, receptors, metrics,
                                         diet_fractions = 1.0)

engine_acute   <- engine_summary[engine_summary$metric_id == "bird_acute_screening", ]
engine_chronic <- engine_summary[engine_summary$metric_id == "bird_chronic_screening", ]

cat("Part 18. Side-by-side comparison: hand calculation vs. R engine\n")
cat("(Small differences at the 1e-9 level or smaller are floating-point\n")
cat(" rounding, not a disagreement.)\n\n")

comparison <- data.frame(
  quantity = c(
    "seed_mass_g", "seeds_per_ha", "seeds_per_m2",
    "initial_surface_seeds_per_m2", "dose_per_seed_mg",
    "field_rate_g_ai_per_ha", "food_intake_g_dw_per_day (small bird)",
    "seeds_required_per_day (100% diet)", "EDE / initial dose (100% diet)",
    "RQ (acute screening)", "RQ (chronic screening)"
  ),
  hand_calculated = c(
    hand$seed_mass_g, hand$seeds_per_ha, hand$seeds_per_m2,
    hand$initial_surface_seeds_per_m2, hand$dose_per_seed_mg,
    hand$field_rate_g_ai_per_ha, hand$food_intake_g_dw_per_day,
    hand$seeds_required_per_day_full_diet, hand$ede_full_diet,
    hand$rq_acute, hand$rq_chronic
  ),
  r_engine = c(
    engine_row$seed_mass_g, engine_row$seeds_per_ha, engine_row$seeds_per_m2,
    engine_row$initial_surface_seeds_per_m2, engine_row$dose_per_seed_mg,
    engine_row$field_rate_g_ai_per_ha, receptors$food_intake_g_dw_per_day,
    engine_acute$seeds_required_per_day, engine_acute$initial_dose_mg_kg_bw_day,
    engine_acute$initial_rq, engine_chronic$initial_rq
  )
)
comparison$relative_difference <- ifelse(
  comparison$hand_calculated == 0, NA,
  abs(comparison$r_engine - comparison$hand_calculated) /
    abs(comparison$hand_calculated)
)
comparison$agrees <- ifelse(
  is.na(comparison$relative_difference), comparison$r_engine == 0,
  comparison$relative_difference < 1e-9
)

print(comparison, digits = 10, row.names = FALSE)

cat("\n")
if (all(comparison$agrees)) {
  cat("RESULT: every hand-calculated value agrees with the R engine to\n")
  cat("within 1e-9 relative difference.\n")
} else {
  cat("RESULT: at least one value DOES NOT agree with the R engine.\n")
  cat("Do not treat this as validated -- investigate the disagreeing row(s)\n")
  cat("above before relying on this scenario.\n")
}

cat("\nThis script checked ONE scenario in detail. It is a teaching and\n")
cat("spot-check tool, not a substitute for the full test suite\n")
cat("(tests/testthat/, 424 assertions) or the independent adversarial audit\n")
cat("(docs/independent_engine_audit.md). Re-run this script with different\n")
cat("crops/rates/receptors by editing Part 1 and Part 8 above -- every\n")
cat("later part recalculates automatically from those inputs.\n")
