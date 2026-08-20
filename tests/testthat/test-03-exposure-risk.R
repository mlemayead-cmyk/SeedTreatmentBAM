# Exposure, risk quotients and durations. Specification section 9.

test_that("food ingestion rate follows the stored Nagy regressions", {
  expect_equal(food_requirement(20, 0.398, 0.85), 5.078770266809547,
               tolerance = 1e-12)
  expect_equal(food_requirement(100, 0.398, 0.85), 19.94725189836544,
               tolerance = 1e-12)
  expect_equal(food_requirement(1000, 0.648, 0.651), 58.153385883648525,
               tolerance = 1e-12)
  expect_equal(food_requirement(15, 0.235, 0.822), 2.176781697501487,
               tolerance = 1e-12)
  expect_equal(food_requirement(35, 0.235, 0.822), 4.3680921800285555,
               tolerance = 1e-12)
  expect_equal(food_requirement(1000, 0.235, 0.822), 68.71758087931835,
               tolerance = 1e-12)
})

test_that("seeds required per day scales with the dietary fraction", {
  expect_equal(seeds_required_per_day(5.078770266809547, 0.013),
               390.674636, tolerance = 1e-6)
  expect_equal(seeds_required_per_day(19.94725189836544, 0.0065),
               3068.807984, tolerance = 1e-6)
  expect_equal(seeds_required_per_day(58.153385883648525, 0.013),
               4473.337376, tolerance = 1e-6)
  expect_equal(seeds_required_per_day(5.078770266809547, 0.013, 0.25),
               390.674636 / 4, tolerance = 1e-6)
  expect_equal(seeds_required_per_day(5.078770266809547, 0.013, 0), 0)
})

test_that("estimated daily exposure reproduces the audited values", {
  expect_equal(estimated_daily_exposure(300, 5.078770266809547, 20, 1),
               76.181554, tolerance = 1e-6)
  expect_equal(estimated_daily_exposure(300, 19.94725189836544, 100, 0.25),
               14.960439, tolerance = 1e-6)
  expect_equal(estimated_daily_exposure(200, 58.153385883648525, 1000, 0.5),
               5.815339, tolerance = 1e-6)
  expect_equal(estimated_daily_exposure(200, 19.94725189836544, 100, 0.01),
               0.398945, tolerance = 1e-6)
})

test_that("the concentration and per-seed exposure forms agree", {
  concentration <- 300
  tkw <- 24.8
  seed_mass <- seed_mass_from_tkw(tkw)
  fir <- 5.078770266809547
  bw <- 20
  for (diet in c(1, 0.5, 0.25, 0.1, 0.01)) {
    by_concentration <- estimated_daily_exposure(concentration, fir, bw, diet)
    dose_per_seed <- treatment_loading(concentration, "mg a.i./kg seed",
                                       tkw)$dose_per_seed_mg
    seeds <- seeds_required_per_day(fir, seed_mass, diet)
    by_seed <- daily_ai_intake_dose(seeds, dose_per_seed, bw)
    expect_equal(by_concentration, by_seed, tolerance = 1e-12)
  }
})

test_that("exposure does not depend on seed mass for a mass-basis rate", {
  a <- estimated_daily_exposure(300, 5.078770266809547, 20, 1)
  b <- estimated_daily_exposure(300, 5.078770266809547, 20, 1)
  expect_identical(a, b)
  # Seed mass appears nowhere in the concentration form.
  expect_false("seed_mass_g" %in% names(formals(estimated_daily_exposure)))
})

test_that("risk quotient is dose divided by the effects metric", {
  expect_equal(risk_quotient(76.181554, 43.1), 76.181554 / 43.1)
  expect_equal(risk_quotient(76.2, 43.1), 1.767981, tolerance = 1e-6)
  expect_equal(risk_quotient(76.2, 7.78), 9.794344, tolerance = 1e-6)
  expect_equal(risk_quotient(0, 43.1), 0)
})

test_that("duration above a metric reproduces the audited values", {
  expect_equal(duration_above_effect_metric(76.181554, 43.1, 10),
               8.217538, tolerance = 1e-6)
  expect_equal(duration_above_effect_metric(50.787703, 7.78, 10),
               27.066372, tolerance = 1e-6)
  expect_equal(duration_above_effect_metric(59.841756, 7.78, 10),
               29.433104, tolerance = 1e-6)
  expect_equal(duration_above_effect_metric(14.960439, 7.78, 10),
               9.433104, tolerance = 1e-6)
  expect_equal(duration_above_effect_metric(17.446016, 7.78, 10),
               11.650555, tolerance = 1e-6)
})

test_that("duration is zero, never negative, when the metric is not reached", {
  expect_equal(duration_above_effect_metric(5, 43.1, 10), 0)
  expect_equal(duration_above_effect_metric(43.1, 43.1, 10), 0)
  expect_equal(duration_above_effect_metric(0, 43.1, 10), 0)
  out <- duration_above_effect_metric(c(1, 50, 100), 43.1, 10)
  expect_true(all(out >= 0))
  expect_equal(out[1], 0)
})

test_that("non-dissipating residues never fall below the metric", {
  expect_equal(duration_above_effect_metric(100, 43.1, Inf), Inf)
  expect_equal(duration_above_effect_metric(10, 43.1, Inf), 0)
})

test_that("dose at the duration endpoint equals the effects metric", {
  days <- duration_above_effect_metric(76.181554, 43.1, 10)
  expect_equal(daily_dose_over_time(76.181554, days, 10), 43.1,
               tolerance = 1e-9)
})

test_that("threshold dietary fraction reproduces the audited value", {
  expect_equal(threshold_diet_fraction_pct(76.181554, 7.78), 10.21,
               tolerance = 1e-3)
  expect_equal(threshold_diet_fraction_pct(0, 7.78), Inf)
})

test_that("seeds to reach a metric uses body weight in kilograms", {
  expect_equal(seeds_to_effect_metric(43.1, 20, 0.00744),
               43.1 * 0.020 / 0.00744, tolerance = 1e-12)
  expect_equal(seeds_to_effect_metric(43.1, 20, 0), Inf)
})
