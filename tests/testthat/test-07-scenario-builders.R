# Canonical dataset builders, and exact reproduction of the workbook bounds.

baseline <- load_baseline()
params <- parameter_set(baseline)

test_that("the baseline loads with the expected reference tables", {
  expect_s3_class(baseline, "stbam_baseline")
  expect_gt(nrow(baseline$crops), 80)
  expect_equal(nrow(baseline$planting_methods), 4)
  expect_equal(nrow(baseline$receptors), 6)
  expect_true(all(c("bird_small", "bird_medium", "bird_large", "mammal_small",
                    "mammal_medium", "mammal_large") %in%
                    baseline$receptors$receptor_id))
})

test_that("the mammalian chronic workflow stages are kept separate", {
  metrics <- baseline$effects_metrics
  screening <- metrics[metrics$metric_id == "mammal_chronic_screening", ]
  refined <- metrics[metrics$metric_id == "mammal_chronic_refined", ]
  expect_equal(nrow(screening), 1L)
  expect_equal(nrow(refined), 1L)
  expect_equal(screening$effects_metric, 1.8)
  expect_equal(refined$effects_metric, 2.4)
  expect_equal(screening$metric_role, "SCREENING")
  expect_equal(refined$metric_role, "REFINED")
})

test_that("planting-method surface fractions match the assessment", {
  methods <- baseline$planting_methods
  fraction <- function(id) {
    methods$surface_seed_fraction[methods$planting_method == id]
  }
  expect_equal(fraction("broadcast"), 1)
  expect_equal(fraction("drill_spring"), 0.033)
  expect_equal(fraction("drill_fall"), 0.092)
  expect_equal(fraction("precision"), 0.005)
})

barley <- build_scenario_inputs(params, crops = "Barley",
                                workbooks = "small_cereals",
                                rate_levels = "high",
                                planting_methods = "broadcast")

test_that("a directly supplied seed count is the primary datum", {
  expect_equal(nrow(barley), 4L)
  expect_true(all(barley$seeding_basis == "SEED_COUNT_SUPPLIED"))
  low <- barley[barley$seeding_rate_bound == "low", ]
  high <- barley[barley$seeding_rate_bound == "high", ]
  expect_true(all(low$seeds_per_ha == 1.8e6))
  expect_true(all(high$seeds_per_ha == 4.7e6))
})

test_that("barley reproduces the workbook's stored values exactly", {
  pick <- function(rate_bound, mass_bound) {
    barley[barley$seeding_rate_bound == rate_bound &
             barley$seed_mass_bound == mass_bound, ]
  }
  # Workbook 'Seed Inputs and EECs' row 4.
  expect_equal(pick("low", "low_tkw")$dose_per_seed_mg, 0.00744,
               tolerance = 1e-12)                                   # Q4
  expect_equal(pick("high", "high_tkw")$dose_per_seed_mg, 0.01785,
               tolerance = 1e-12)                                   # R4
  expect_equal(pick("low", "low_tkw")$seeding_rate_kg_per_ha, 44.64,
               tolerance = 1e-9)                                    # F4
  expect_equal(pick("low", "high_tkw")$seeding_rate_kg_per_ha, 107.1,
               tolerance = 1e-9)                                    # G4
  expect_equal(pick("high", "low_tkw")$seeding_rate_kg_per_ha, 116.56,
               tolerance = 1e-9)                                    # H4
  expect_equal(pick("high", "high_tkw")$seeding_rate_kg_per_ha, 279.65,
               tolerance = 1e-9)                                    # I4
  expect_equal(pick("low", "low_tkw")$field_rate_g_ai_per_ha, 13.392,
               tolerance = 1e-9)                                    # W4
  expect_equal(pick("high", "high_tkw")$field_rate_g_ai_per_ha, 83.895,
               tolerance = 1e-9)                                    # X4
  expect_equal(pick("low", "low_tkw")$initial_surface_seeds_per_m2, 180)   # AC4
  expect_equal(pick("high", "low_tkw")$initial_surface_seeds_per_m2, 470)  # AD4
  expect_equal(pick("low", "low_tkw")$area_per_surface_seed_m2,
               5.5555555555555558e-3, tolerance = 1e-12)            # AK4
  expect_equal(pick("high", "low_tkw")$area_per_surface_seed_m2,
               2.1276595744680851e-3, tolerance = 1e-12)            # AL4
})

test_that("a mass-supplied seeding rate is the primary datum", {
  oat <- build_scenario_inputs(params, crops = "Oat",
                               workbooks = "small_cereals",
                               rate_levels = "high",
                               planting_methods = "broadcast")
  expect_true(all(oat$seeding_basis == "MASS_RATE_SUPPLIED"))
  low_high_tkw <- oat[oat$seeding_rate_bound == "low" &
                        oat$seed_mass_bound == "high_tkw", ]
  high_low_tkw <- oat[oat$seeding_rate_bound == "high" &
                        oat$seed_mass_bound == "low_tkw", ]
  # 'Seeding Assumptions' K62 and L62.
  expect_equal(low_high_tkw$seeds_per_ha, 1169565.2173913042, tolerance = 1e-6)
  expect_equal(high_low_tkw$seeds_per_ha, 5814814.8148148144, tolerance = 1e-6)
  # The supplied mass rate is preserved on both seed-mass bounds.
  expect_equal(unique(oat$seeding_rate_kg_per_ha[
    oat$seeding_rate_bound == "low"
  ]), 53.8)
  expect_equal(unique(oat$seeding_rate_kg_per_ha[
    oat$seeding_rate_bound == "high"
  ]), 157)
})

test_that("the published low and high bounds are corners of the grid", {
  for (crop in c("Oat", "Buckwheat", "Millet, pearl", "Rye", "Triticale")) {
    inputs <- build_scenario_inputs(params, crops = crop,
                                    workbooks = "small_cereals",
                                    rate_levels = "high",
                                    planting_methods = "broadcast")
    crop_row <- baseline$crops[baseline$crops$crop == crop, ][1, ]
    expect_equal(min(inputs$seeds_per_ha), crop_row$seeds_per_ha_low,
                 tolerance = 1e-6, info = crop)
    expect_equal(max(inputs$seeds_per_ha), crop_row$seeds_per_ha_high,
                 tolerance = 1e-6, info = crop)
  }
})

test_that("only agronomically available planting methods are generated", {
  # Barley is spring and fall seeded, broadcast and drilled, not precision.
  all_methods <- build_scenario_inputs(params, crops = "Barley",
                                       workbooks = "small_cereals",
                                       rate_levels = "high")
  expect_setequal(unique(all_methods$planting_method),
                  c("broadcast", "drill_spring", "drill_fall"))
  expect_false("precision" %in% all_methods$planting_method)

  # Sorghum is not fall seeded.
  sorghum <- build_scenario_inputs(params, crops = "Sorghum",
                                   workbooks = "small_cereals",
                                   rate_levels = "high")
  expect_false("drill_fall" %in% sorghum$planting_method)
})

test_that("the summary reproduces the audited screening risk quotients", {
  inputs <- build_scenario_inputs(params, crops = "Barley",
                                  workbooks = "small_cereals",
                                  rate_levels = "high",
                                  planting_methods = "broadcast")
  summary <- build_scenario_summary(
    params, inputs,
    receptors = resolve_receptors(params, "bird_small"),
    diet_fractions = 1
  )
  acute <- summary[summary$metric_id == "bird_acute_screening", ]
  chronic <- summary[summary$metric_id == "bird_chronic_screening", ]
  expect_equal(unique(round(acute$ede_full_diet, 6)), 76.181554)
  expect_equal(unique(round(acute$screening_rq, 6)), 1.767553)
  expect_equal(unique(round(chronic$screening_rq, 6)), 9.791974)
  expect_equal(unique(round(acute$days_above_loc, 6)), 8.217538)
  expect_equal(unique(round(chronic$threshold_diet_fraction_pct, 2)), 10.21)
})

test_that("the summary and the daily time course agree at day zero", {
  inputs <- build_scenario_inputs(params, crops = "Barley",
                                  workbooks = "small_cereals",
                                  rate_levels = "high",
                                  planting_methods = "broadcast")
  receptors <- resolve_receptors(params, "bird_small")
  metrics <- resolve_effects_metrics(params)
  summary <- build_scenario_summary(params, inputs, receptors, metrics,
                                    diet_fractions = c(1, 0.25))
  timecourse <- build_daily_timecourse(params, inputs, receptors, metrics,
                                       diet_fractions = c(1, 0.25),
                                       days = 0:30)
  day0 <- timecourse[timecourse$day == 0, ]
  key <- c("scenario_id", "receptor_id", "metric_id", "diet_fraction")
  joined <- merge(day0[, c(key, "dose_mg_kg_bw_day", "rq")],
                  summary[, c(key, "initial_dose_mg_kg_bw_day", "initial_rq")],
                  by = key)
  expect_gt(nrow(joined), 0)
  expect_equal(joined$dose_mg_kg_bw_day, joined$initial_dose_mg_kg_bw_day)
  expect_equal(joined$rq, joined$initial_rq)
})

test_that("the daily dose crosses the metric at the summarised duration", {
  inputs <- build_scenario_inputs(params, crops = "Barley",
                                  workbooks = "small_cereals",
                                  rate_levels = "high",
                                  planting_methods = "broadcast")
  receptors <- resolve_receptors(params, "bird_small")
  metrics <- resolve_effects_metrics(params)
  summary <- build_scenario_summary(params, inputs, receptors, metrics,
                                    diet_fractions = 1)
  row <- summary[summary$metric_id == "bird_acute_screening", ][1, ]
  timecourse <- build_daily_timecourse(
    params, inputs[inputs$scenario_id == row$scenario_id, ], receptors,
    metrics, diet_fractions = 1,
    days = c(floor(row$days_above_loc), ceiling(row$days_above_loc))
  )
  timecourse <- timecourse[timecourse$metric_id == "bird_acute_screening", ]
  expect_true(any(timecourse$rq >= 1))
  expect_true(any(timecourse$rq < 1))
})

test_that("overrides change results and never mutate the baseline", {
  before <- baseline$crops$tkw_low_g_per_1000[baseline$crops$crop == "Barley"]
  changed <- set_override(params, "tkw_g_per_1000", 30,
                          scope = "Barley:low_tkw", baseline_value = before)
  inputs <- build_scenario_inputs(changed, crops = "Barley",
                                  workbooks = "small_cereals",
                                  rate_levels = "high",
                                  planting_methods = "broadcast")
  low <- inputs[inputs$seed_mass_bound == "low_tkw", ]
  expect_true(all(low$tkw_g_per_1000 == 30))
  expect_true(all(low$tkw_status == "USER_OVERRIDE"))

  # The baseline object and the original parameter set are untouched.
  expect_equal(baseline$crops$tkw_low_g_per_1000[baseline$crops$crop == "Barley"],
               before)
  expect_false(has_overrides(params))
  expect_true(has_overrides(changed))
})

test_that("a body-weight override propagates into the food-intake regression", {
  changed <- set_override(params, "body_weight_g", 40, scope = "bird_small")
  receptors <- resolve_receptors(changed, "bird_small")
  expect_equal(receptors$body_weight_g, 40)
  expect_equal(receptors$food_intake_g_dw_per_day,
               food_requirement(40, 0.398, 0.85), tolerance = 1e-12)
  expect_false(isTRUE(all.equal(receptors$food_intake_g_dw_per_day,
                                5.078770266809547)))
})

test_that("a seeds_per_ha override propagates into the mass seeding rate (AUD-094)", {
  # Independent audit finding: overriding seeds_per_ha correctly raised the
  # surface seed density but left seeding_rate_kg_per_ha (and hence
  # field_rate_g_ai_per_ha) at the pre-override value, silently violating the
  # row's own identity seeds_per_ha x TKW / 1e6 = seeding_rate_kg_per_ha.
  baseline_rows <- build_scenario_inputs(
    params, crops = "Barley", workbooks = "small_cereals", rate_levels = "high",
    planting_methods = "broadcast"
  )
  before <- baseline_rows[baseline_rows$seeding_rate_bound == "low" &
                             baseline_rows$seed_mass_bound == "low_tkw", ]
  expect_equal(before$seeds_per_ha, 1800000)
  expect_equal(before$seeding_rate_kg_per_ha, 44.64, tolerance = 1e-9)

  changed <- set_override(params, "seeds_per_ha", 2400000, scope = "Barley:low",
                          baseline_value = 1800000, source = "Test")
  after_rows <- build_scenario_inputs(
    changed, crops = "Barley", workbooks = "small_cereals", rate_levels = "high",
    planting_methods = "broadcast"
  )
  after <- after_rows[after_rows$seeding_rate_bound == "low" &
                         after_rows$seed_mass_bound == "low_tkw", ]

  expect_equal(after$seeds_per_ha, 2400000)
  expect_equal(after$initial_surface_seeds_per_m2, 240)   # 2,400,000 / 10,000
  # The consistent mass rate at TKW 24.8 is 2,400,000 x 24.8 / 1e6 = 59.52,
  # not the stale pre-override 44.64.
  expect_equal(after$seeding_rate_kg_per_ha, 59.52, tolerance = 1e-9)
  expect_equal(after$field_rate_g_ai_per_ha, 0.3 * 59.52, tolerance = 1e-9)

  # The row's own round-trip identity holds again after the fix.
  expect_equal(after$seeds_per_ha * after$tkw_g_per_1000 / 1e6,
               after$seeding_rate_kg_per_ha, tolerance = 1e-12)

  # An explicit mass-rate override still takes precedence over the derived
  # value, exactly like the food-intake override test below.
  both <- set_override(changed, "seeding_rate_kg_per_ha", 100,
                       scope = "Barley:low", source = "Test")
  both_rows <- build_scenario_inputs(
    both, crops = "Barley", workbooks = "small_cereals", rate_levels = "high",
    planting_methods = "broadcast"
  )
  both_low <- both_rows[both_rows$seeding_rate_bound == "low" &
                           both_rows$seed_mass_bound == "low_tkw", ]
  expect_equal(both_low$seeding_rate_kg_per_ha, 100)
})

test_that("an explicit food-intake override takes precedence", {
  changed <- set_override(params, "food_intake_g_dw_per_day", 7,
                          scope = "bird_small")
  receptors <- resolve_receptors(changed, "bird_small")
  expect_equal(receptors$food_intake_g_dw_per_day, 7)
  expect_equal(receptors$body_weight_g, 20)
})

test_that("scenario configurations round trip through CSV", {
  path <- withr::local_tempfile(fileext = ".csv")
  changed <- set_override(params, "residue_dt50_days", 21, scope = "global",
                          baseline_value = 10, source = "Test")
  changed <- set_override(changed, "tkw_g_per_1000", 33,
                          scope = "Barley:low_tkw", baseline_value = 24.8)
  changed$name <- "Updated agronomy"
  export_scenario_config(changed, path)

  reloaded <- import_scenario_config(baseline, path)
  expect_equal(reloaded$name, "Updated agronomy")
  expect_equal(nrow(reloaded$overrides), 2L)
  expect_setequal(reloaded$overrides$parameter,
                  c("residue_dt50_days", "tkw_g_per_1000"))
  expect_equal(
    reloaded$overrides$value[reloaded$overrides$parameter == "residue_dt50_days"],
    21
  )
})

test_that("resetting returns exactly to the baseline", {
  changed <- set_override(params, "residue_dt50_days", 21)
  expect_true(has_overrides(changed))
  expect_false(has_overrides(reset_to_baseline(changed)))

  a <- build_scenario_inputs(params, crops = "Barley",
                             workbooks = "small_cereals", rate_levels = "high")
  b <- build_scenario_inputs(reset_to_baseline(changed), crops = "Barley",
                             workbooks = "small_cereals", rate_levels = "high")
  expect_equal(a$initial_surface_seeds_per_m2, b$initial_surface_seeds_per_m2)
  expect_equal(a$dose_per_seed_mg, b$dose_per_seed_mg)
})

test_that("an unknown override parameter or bad value is rejected", {
  expect_error(set_override(params, "not_a_parameter", 1), "Unknown")
  expect_error(set_override(params, "surface_seed_fraction", 1.5), "at most 1")
  expect_error(set_override(params, "residue_dt50_days", -1), "must be at least")
  expect_error(set_override(params, "residue_dt50_days", c(1, 2)),
               "single value")
  expect_error(set_override(params, "residue_dt50_days", 10,
                            status = "ASSESSMENT_DEFAULT"), "Unknown")
})

test_that("empty or impossible selections raise a clear error", {
  expect_error(build_scenario_inputs(params, crops = "Not A Crop"),
               "No crop x rate scenarios matched")
  expect_error(
    build_scenario_inputs(params, crops = "Barley",
                          workbooks = "small_cereals",
                          planting_methods = "precision"),
    "No scenarios could be built"
  )
  expect_error(resolve_effects_metrics(params, metric_roles = "NONSENSE"),
               "No effects metrics matched")
})

test_that("no canonical result contains an unexpected missing value", {
  inputs <- build_scenario_inputs(params, workbooks = "small_cereals",
                                  rate_levels = "high")
  critical <- c("seed_mass_g", "seeds_per_ha", "seeding_rate_kg_per_ha",
                "concentration_mg_per_kg_seed", "dose_per_seed_mg",
                "field_rate_g_ai_per_ha", "initial_surface_seeds_per_m2")
  for (column in critical) {
    expect_false(anyNA(inputs[[column]]), info = column)
  }
  summary <- build_scenario_summary(params, inputs, diet_fractions = 1)
  for (column in c("ede_full_diet", "screening_rq", "peak_rq",
                   "days_above_loc", "initial_max_feasible_diet_fraction")) {
    expect_false(anyNA(summary[[column]]), info = column)
  }
})
