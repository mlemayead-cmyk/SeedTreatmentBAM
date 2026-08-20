# Maximum obtainable exposure: MSA policy, availability-constrained
# calculation, figure metadata, and summary annotations.
#
# Baseline scenario throughout: Barley, high rate (300 mg a.i./kg seed),
# broadcast, low seeding-rate bound / low TKW -- the same audited scenario
# used in test-07 and scripts/reviewer_validation_walkthrough.R, so several
# expected values below are independently checkable there.

baseline <- load_baseline()
params <- parameter_set(baseline)
barley <- build_scenario_inputs(params, crops = "Barley",
                                workbooks = "small_cereals",
                                rate_levels = "high",
                                planting_methods = "broadcast")
low_low <- barley[barley$seeding_rate_bound == "low" &
                    barley$seed_mass_bound == "low_tkw", ]
bird_receptors <- resolve_receptors(params, "bird_small")
bird_metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "bird")
tc <- build_daily_timecourse(params, low_low, bird_receptors, bird_metrics,
                             diet_fractions = 1, days = 0:100)

# --- MSA policy (specification section 10.4 / MAIN-P000209) ---------------

test_that("resolve_msa_term_for_metric follows the assessment's own MSA policy", {
  expect_equal(resolve_msa_term_for_metric("bird", "acute"), "short")
  expect_equal(resolve_msa_term_for_metric("bird", "chronic"), "short")
  expect_equal(resolve_msa_term_for_metric("mammal", "acute"), "short")
  expect_equal(resolve_msa_term_for_metric("mammal", "chronic"), "long")
})

test_that("birds use the short-term MSA for both acute and chronic screening rows", {
  acute <- tc[tc$duration_class == "acute", ]
  chronic <- tc[tc$duration_class == "chronic", ]
  expect_true(all(acute$max_obtainable_msa_term == "short"))
  expect_true(all(chronic$max_obtainable_msa_term == "short"))
  expect_true(all(acute$max_obtainable_msa_m2 == 70))
  expect_true(all(chronic$max_obtainable_msa_m2 == 70))
})

test_that("mammal acute and chronic characterization use different MSA terms", {
  mammal_receptors <- resolve_receptors(params, "mammal_small")
  mammal_metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "mammal")
  mammal_tc <- build_daily_timecourse(params, low_low, mammal_receptors,
                                      mammal_metrics, diet_fractions = 1,
                                      days = 0)
  acute <- mammal_tc[mammal_tc$duration_class == "acute", ]
  chronic <- mammal_tc[mammal_tc$duration_class == "chronic", ]
  expect_true(nrow(acute) > 0 && nrow(chronic) > 0)
  expect_true(all(acute$max_obtainable_msa_term == "short"))
  expect_true(all(chronic$max_obtainable_msa_term == "long"))
  expect_true(all(acute$max_obtainable_msa_m2 == 70))
  expect_true(all(chronic$max_obtainable_msa_m2 == 35))
})

# --- Availability cap -------------------------------------------------------

test_that("max_obtainable_seeds_per_day never exceeds either input", {
  expect_equal(max_obtainable_seeds_per_day(100, 50), 50)
  expect_equal(max_obtainable_seeds_per_day(50, 100), 50)
  expect_equal(max_obtainable_seeds_per_day(0, 100), 0)
  expect_equal(max_obtainable_seeds_per_day(100, 0), 0)
})

test_that("maximum-obtainable seed consumption never exceeds availability or requirement, over the full grid", {
  expect_true(all(tc$max_obtainable_seeds_per_day <=
                    tc$max_obtainable_seeds_within_msa + 1e-9))
  expect_true(all(tc$max_obtainable_seeds_per_day <=
                    tc$seeds_required_per_day + 1e-9))
})

# --- Abundant-seed vs. seed-limited conditions -----------------------------

test_that("abundant surface seed: maximum-obtainable RQ equals conditional RQ", {
  acute0 <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 0, ]
  expect_equal(nrow(acute0), 1L)
  expect_equal(acute0$max_obtainable_rq, acute0$rq, tolerance = 1e-9)
  expect_equal(acute0$max_obtainable_dose_mg_kg_bw_day,
               acute0$initial_dose_mg_kg_bw_day, tolerance = 1e-9)
})

test_that("seed-scarce surface seed: maximum-obtainable RQ is strictly below conditional RQ", {
  # Day 83.2 is the audited crossing point (workbook 1!N79, reproduced in
  # docs/independent_engine_audit.md section 6.1); day 95 is comfortably past it.
  acute95 <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 95, ]
  expect_equal(nrow(acute95), 1L)
  expect_lt(acute95$max_obtainable_rq, acute95$rq)
  expect_lt(acute95$max_obtainable_seeds_per_day, acute95$seeds_required_per_day)
})

# --- Zero surface seed -------------------------------------------------------

test_that("zero surface seed gives zero maximum-obtainable exposure", {
  zero_params <- set_override(params, "surface_seed_fraction", 0,
                              scope = "broadcast")
  zero_inputs <- build_scenario_inputs(zero_params, crops = "Barley",
                                       workbooks = "small_cereals",
                                       rate_levels = "high",
                                       planting_methods = "broadcast")
  zero_low <- zero_inputs[zero_inputs$seeding_rate_bound == "low" &
                            zero_inputs$seed_mass_bound == "low_tkw", ]
  zero_tc <- build_daily_timecourse(zero_params, zero_low, bird_receptors,
                                    bird_metrics, diet_fractions = 1, days = 0)
  expect_true(all(zero_tc$max_obtainable_seeds_within_msa == 0))
  expect_true(all(zero_tc$max_obtainable_seeds_per_day == 0))
  expect_true(all(zero_tc$max_obtainable_dose_mg_kg_bw_day == 0))
  expect_true(all(zero_tc$max_obtainable_rq == 0))
  # The conditional (100%-diet) calculation is entirely unaffected: it does
  # not depend on surface seed at all. Compare metric by metric, since
  # zero_tc and base0 both carry every screening metric.
  base0 <- tc[tc$day == 0, ]
  zero_by_metric <- zero_tc$rq[order(zero_tc$metric_id)]
  base_by_metric <- base0$rq[order(base0$metric_id)]
  expect_equal(sort(unique(zero_tc$metric_id)), sort(unique(base0$metric_id)))
  expect_equal(zero_by_metric, base_by_metric)
})

# --- MSA changes affect availability only, never the conditional RQ --------

test_that("changing MSA changes maximum-obtainable exposure but not conditional dose/RQ", {
  msa_params <- set_override(params, "msa_m2", 1, scope = "bird_small")
  msa_receptors <- resolve_receptors(msa_params, "bird_small", msa_term = "short")
  msa_tc <- build_daily_timecourse(msa_params, low_low, msa_receptors,
                                   bird_metrics, diet_fractions = 1, days = 0)
  base0 <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 0, ]
  msa0 <- msa_tc[msa_tc$metric_id == "bird_acute_screening" & msa_tc$day == 0, ]

  expect_equal(msa0$rq, base0$rq)
  expect_equal(msa0$initial_dose_mg_kg_bw_day, base0$initial_dose_mg_kg_bw_day)
  expect_lt(msa0$max_obtainable_rq, base0$max_obtainable_rq)
  expect_lt(msa0$max_obtainable_seeds_within_msa,
           base0$max_obtainable_seeds_within_msa)
})

# --- Surface-seed DT50 affects availability, never residue per seed --------

test_that("surface-seed DT50 affects maximum-obtainable exposure but not residue per seed", {
  fast_params <- set_override(params, "surface_seed_dt50_days", 3,
                              scope = "global")
  fast_tc <- build_daily_timecourse(fast_params, low_low, bird_receptors,
                                    bird_metrics, diet_fractions = 1,
                                    days = c(0, 30))
  base_tc <- build_daily_timecourse(params, low_low, bird_receptors,
                                    bird_metrics, diet_fractions = 1,
                                    days = c(0, 30))

  expect_equal(fast_tc$ai_per_seed_mg, base_tc$ai_per_seed_mg)
  expect_equal(fast_tc$rq, base_tc$rq)   # conditional is residue-driven only

  fast30 <- fast_tc[fast_tc$day == 30 & fast_tc$metric_id == "bird_acute_screening", ]
  base30 <- base_tc[base_tc$day == 30 & base_tc$metric_id == "bird_acute_screening", ]
  expect_lt(fast30$max_obtainable_seeds_within_msa,
           base30$max_obtainable_seeds_within_msa)
})

# --- Residue DT50 affects dose/RQ, never the surface seed count -----------

test_that("residue DT50 affects dose/RQ but not surface seed count or availability", {
  fast_res <- set_override(params, "residue_dt50_days", 3, scope = "global")
  fast_tc <- build_daily_timecourse(fast_res, low_low, bird_receptors,
                                    bird_metrics, diet_fractions = 1,
                                    days = c(0, 30))
  base_tc <- build_daily_timecourse(params, low_low, bird_receptors,
                                    bird_metrics, diet_fractions = 1,
                                    days = c(0, 30))

  expect_equal(fast_tc$surface_seeds_per_m2, base_tc$surface_seeds_per_m2)
  expect_equal(fast_tc$max_obtainable_seeds_within_msa,
               base_tc$max_obtainable_seeds_within_msa)

  fast30 <- fast_tc[fast_tc$day == 30 & fast_tc$metric_id == "bird_acute_screening", ]
  base30 <- base_tc[base_tc$day == 30 & base_tc$metric_id == "bird_acute_screening", ]
  expect_lt(fast30$rq, base30$rq)
  expect_lt(fast30$max_obtainable_rq, base30$max_obtainable_rq)
})

# --- Treatment loading affects both curves appropriately --------------------

test_that("increasing treatment loading increases both conditional and maximum-obtainable dose/RQ", {
  high_rate <- set_override(params, "application_rate", 600,
                            scope = "Barley:high")
  high_inputs <- build_scenario_inputs(high_rate, crops = "Barley",
                                       workbooks = "small_cereals",
                                       rate_levels = "high",
                                       planting_methods = "broadcast")
  high_low <- high_inputs[high_inputs$seeding_rate_bound == "low" &
                            high_inputs$seed_mass_bound == "low_tkw", ]
  high_tc <- build_daily_timecourse(high_rate, high_low, bird_receptors,
                                    bird_metrics, diet_fractions = 1, days = 0)

  base0 <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 0, ]
  high0 <- high_tc[high_tc$metric_id == "bird_acute_screening" & high_tc$day == 0, ]

  expect_gt(high0$initial_dose_mg_kg_bw_day, base0$initial_dose_mg_kg_bw_day)
  expect_gt(high0$rq, base0$rq)
  expect_gt(high0$max_obtainable_dose_mg_kg_bw_day,
           base0$max_obtainable_dose_mg_kg_bw_day)
  expect_gt(high0$max_obtainable_rq, base0$max_obtainable_rq)
})

# --- Effects metric changes RQ only -----------------------------------------

test_that("changing the effects metric changes RQ but not dose or seed availability", {
  acute0 <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 0, ]
  chronic0 <- tc[tc$metric_id == "bird_chronic_screening" & tc$day == 0, ]
  expect_equal(acute0$initial_dose_mg_kg_bw_day,
               chronic0$initial_dose_mg_kg_bw_day)
  expect_equal(acute0$max_obtainable_dose_mg_kg_bw_day,
               chronic0$max_obtainable_dose_mg_kg_bw_day)
  expect_equal(acute0$max_obtainable_seeds_within_msa,
               chronic0$max_obtainable_seeds_within_msa)
  expect_false(isTRUE(all.equal(acute0$rq, chronic0$rq)))
  expect_false(isTRUE(all.equal(acute0$max_obtainable_rq, chronic0$max_obtainable_rq)))
})

# --- Figure metadata and human-readable labels ------------------------------

test_that("format_metric_label produces the documented human-readable form", {
  expect_equal(format_metric_label("bird", "acute", "SCREENING", 43.1),
               "Bird acute screening — 43.1 mg a.i./kg bw/day")
})

test_that("format_scenario_label produces a readable, non-internal label", {
  label <- format_scenario_label(low_low[1, ])
  expect_false(grepl("|", label, fixed = TRUE))   # not the raw scenario_id
  expect_true(grepl("Barley", label, fixed = TRUE))
  expect_true(grepl("low seeding rate", label, fixed = TRUE))
  expect_true(grepl("low TKW", label, fixed = TRUE))
})

test_that("build_figure_metadata gathers real model values, not invented ones", {
  row <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 0, ]
  meta <- build_figure_metadata(row, bird_metrics, params)

  expect_equal(meta$crop, "Barley")
  expect_equal(meta$effects_metric_value, 43.1)
  expect_equal(meta$msa_m2, 70)
  expect_equal(meta$msa_term, "short")
  expect_equal(meta$body_weight_g, 20)
  expect_false(meta$has_overrides)
  expect_equal(meta$model_version, STBAM_MODEL_VERSION)
  expect_equal(meta$loc, STBAM_DEFAULT_LOC)
  expect_match(meta$git_commit, "^[0-9a-f]{12}$")
})

test_that("figure footnotes are self-contained: scenario, receptor, metric, MSA basis and RQ/LOC all present", {
  row <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 0, ]
  meta <- build_figure_metadata(row, bird_metrics, params)
  full <- format_figure_footnotes(meta, detail = "full")

  expect_true(grepl("Barley", full, fixed = TRUE))
  expect_true(grepl("43.1", full, fixed = TRUE))
  expect_true(grepl("Small bird", full, fixed = TRUE))
  expect_true(grepl("20 g", full, fixed = TRUE))
  expect_true(grepl("70 m2", full, fixed = TRUE))
  expect_true(grepl("MAIN-P000209", full, fixed = TRUE))
  expect_true(grepl("RQ = dose / effects metric", full, fixed = TRUE))
  expect_true(grepl("Assessment baseline", full, fixed = TRUE))

  concise <- format_figure_footnotes(meta, detail = "concise")
  expect_lt(nchar(concise), nchar(full))
})

test_that("figure footnotes state clearly when the scenario contains overrides", {
  changed <- set_override(params, "residue_dt50_days", 21, scope = "global",
                          baseline_value = 10, source = "Test")
  changed_tc <- build_daily_timecourse(changed, low_low, bird_receptors,
                                       bird_metrics, diet_fractions = 1,
                                       days = 0)
  row <- changed_tc[changed_tc$metric_id == "bird_acute_screening", ]
  meta <- build_figure_metadata(row, bird_metrics, changed)
  expect_true(meta$has_overrides)
  footnote <- format_figure_footnotes(meta)
  expect_true(grepl("SCENARIO CONTAINS USER OVERRIDES", footnote, fixed = TRUE))
  expect_true(grepl("residue_dt50_days", footnote, fixed = TRUE))
})

# --- Summary annotations, cross-checked against independent/audited values -

test_that("summarise_max_obtainable_exposure matches independently derived closed-form values", {
  summary <- summarise_max_obtainable_exposure(
    tc[tc$metric_id %in% c("bird_acute_screening", "bird_chronic_screening"), ]
  )
  expect_equal(nrow(summary), 2L)

  chronic_row <- summary[summary$metric_id == "bird_chronic_screening", ]
  expect_equal(
    chronic_row$day_conditional_below_loc,
    duration_above_effect_metric(76.1815540021432, 7.78, 10),
    tolerance = 1e-9
  )

  # Independently audited value (docs/independent_engine_audit.md section
  # 6.1, workbook cell 1!N79): 83.20397158607 days at >=100% diet, barley
  # broadcast low, small bird, 70 m2 short-term MSA. Both acute and chronic
  # rows share this because it depends only on surface-seed availability,
  # not on the effects metric.
  expect_equal(summary$day_100pct_diet_unobtainable,
               rep(83.20397158607, 2), tolerance = 1e-6)

  expect_true(all(summary$peak_max_obtainable_rq <= summary$peak_conditional_rq +
                    1e-9))
  expect_true(all(c(
    "day0_seeds_available_within_msa", "day0_seeds_required_100pct_diet",
    "days_above_loc_conditional", "days_above_loc_max_obtainable"
  ) %in% names(summary)))
})

test_that("maximum-obtainable LOC duration is exact in abundant and seed-limited phases", {
  # Abundant seed through the conditional crossing: identical to conditional.
  expect_equal(
    duration_above_max_obtainable_rq(8, 8, 1024, 10, 5),
    5 * log2(8), tolerance = 1e-12
  )
  # Seed-limited from sowing: combined DT50 = 1/(1/10 + 1/5) = 10/3.
  expect_equal(
    duration_above_max_obtainable_rq(8, 4, 0.5, 10, 5),
    (10 / 3) * log2(4), tolerance = 1e-12
  )
  # Initially abundant, then seed-limited before crossing.
  transition <- 10 * log2(2)
  rq_transition <- 16 * 2^(-transition / 20)
  expect_equal(
    duration_above_max_obtainable_rq(16, 16, 2, 10, 20),
    transition + (20 / 3) * log2(rq_transition), tolerance = 1e-12
  )
  expect_equal(duration_above_max_obtainable_rq(0.5, 0.5, 10, 10, 10), 0)
})

# --- Plot functions run without error and are self-contained ---------------

test_that("plot_max_obtainable_exposure builds without error and carries full metadata in its caption", {
  row <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 0, ]
  meta <- build_figure_metadata(row, bird_metrics, params)
  scenario_tc <- tc[tc$metric_id == "bird_acute_screening", ]
  p <- plot_max_obtainable_exposure(scenario_tc, meta, detail = "full")
  expect_s3_class(p, "ggplot")
  expect_true(grepl("MAIN-P000209", p$labels$caption, fixed = TRUE))
})

test_that("plot_seed_availability_vs_requirement builds without error", {
  row <- tc[tc$metric_id == "bird_acute_screening" & tc$day == 0, ]
  meta <- build_figure_metadata(row, bird_metrics, params)
  scenario_tc <- tc[tc$metric_id == "bird_acute_screening", ]
  p <- plot_seed_availability_vs_requirement(scenario_tc, meta)
  expect_s3_class(p, "ggplot")
})

test_that("plot_max_obtainable_small_multiple facets by receptor size with a stated free-y-scale note", {
  all_bird_receptors <- resolve_receptors(
    params, c("bird_small", "bird_medium", "bird_large")
  )
  multi_tc <- build_daily_timecourse(params, low_low, all_bird_receptors,
                                     bird_metrics, diet_fractions = 1,
                                     days = c(0, 10))
  one_metric <- multi_tc[multi_tc$metric_id == "bird_acute_screening", ]
  meta_by_receptor <- stats::setNames(
    lapply(c("bird_small", "bird_medium", "bird_large"), function(id) {
      row <- one_metric[one_metric$receptor_id == id & one_metric$day == 0, ]
      build_figure_metadata(row, bird_metrics, params)
    }),
    c("bird_small", "bird_medium", "bird_large")
  )
  p <- plot_max_obtainable_small_multiple(one_metric, meta_by_receptor)
  expect_s3_class(p, "ggplot")
  expect_no_error(ggplot2::ggplot_build(p))
  expect_true(grepl("independent per panel", p$labels$caption, fixed = TRUE))
  expect_true(grepl("Small bird", p$labels$caption, fixed = TRUE))
  expect_true(grepl("Medium bird", p$labels$caption, fixed = TRUE))
  expect_true(grepl("Large bird", p$labels$caption, fixed = TRUE))

  process <- plot_exposure_processes(one_metric, meta_by_receptor)
  expect_s3_class(process, "ggplot")
  expect_no_error(ggplot2::ggplot_build(process))
  expect_true(grepl("available / required", process$labels$caption,
                    fixed = TRUE))

  fractions <- build_daily_timecourse(
    params, low_low, all_bird_receptors,
    bird_metrics[bird_metrics$metric_id == "bird_acute_screening", ],
    diet_fractions = STBAM_DIET_FRACTIONS, days = c(0, 10)
  )
  dietary <- plot_dietary_fraction_small_multiple(fractions,
                                                   meta_by_receptor)
  expect_s3_class(dietary, "ggplot")
  expect_no_error(ggplot2::ggplot_build(dietary))
  expect_true(grepl("assumed, not demonstrated obtainable",
                    dietary$labels$caption, fixed = TRUE))
})

test_that("dietary-fraction RQ plot labels fractions as assumptions", {
  fractions <- build_daily_timecourse(
    params, low_low, bird_receptors,
    bird_metrics[bird_metrics$metric_id == "bird_acute_screening", ],
    diet_fractions = STBAM_DIET_FRACTIONS, days = c(0, 10)
  )
  meta <- build_figure_metadata(fractions[fractions$day == 0 &
                                           fractions$diet_fraction == 1, ],
                                bird_metrics, params)
  p <- plot_dietary_fraction_rq(fractions, meta)
  expect_s3_class(p, "ggplot")
  expect_true(grepl("assumed, not demonstrated obtainable", p$labels$caption,
                    fixed = TRUE))
})
