# Scientific invariants. Specification section 15.
#
# Only invariants that are scientifically valid are encoded here.

test_that("invariant 1-2: both decay processes are non-increasing", {
  expect_true(all(diff(surface_seed_over_time(180, 0:100, 14)) <= 0))
  expect_true(all(diff(ai_per_seed_over_time(0.00744, 0:100, 10)) <= 0))
})

test_that("invariant 3: no dissipation means a constant residue", {
  expect_equal(ai_per_seed_over_time(0.00744, 0:50, Inf), rep(0.00744, 51))
})

test_that("invariant 4: RQ is exactly dose divided by metric", {
  dose <- runif(200, 0, 200)
  metric <- runif(200, 0.5, 100)
  expect_identical(risk_quotient(dose, metric), dose / metric)
})

test_that("invariant 5: a zero rate zeroes the whole chain", {
  loading <- treatment_loading(0, "mg a.i./kg seed", 24.8)
  expect_equal(loading$dose_per_seed_mg, 0)
  ede <- estimated_daily_exposure(loading$concentration_mg_per_kg_seed,
                                  5.078770266809547, 20, 1)
  expect_equal(ede, 0)
  expect_equal(risk_quotient(ede, 43.1), 0)
  expect_equal(duration_above_effect_metric(ede, 43.1, 10), 0)
})

test_that("invariant 6: a zero dietary fraction zeroes intake", {
  expect_equal(estimated_daily_exposure(300, 5.0788, 20, 0), 0)
  expect_equal(seeds_required_per_day(5.0788, 0.0248, 0), 0)
})

test_that("invariant 7: exposure increases strictly with seed concentration", {
  rates <- c(50, 100, 200, 300, 400)
  ede <- estimated_daily_exposure(rates, 5.078770266809547, 20, 1)
  expect_true(all(diff(ede) > 0))
})

test_that("invariant 8: exposure increases strictly with dietary fraction", {
  fractions <- c(0.01, 0.05, 0.10, 0.25, 0.50, 1.00)
  ede <- estimated_daily_exposure(300, 5.078770266809547, 20, fractions)
  expect_true(all(diff(ede) > 0))
})

test_that("invariant 9: initial surface seed increases with fraction and rate", {
  fractions <- c(0.005, 0.033, 0.092, 1)
  expect_true(all(diff(surface_seed_initial(1.8e6, fractions)) > 0))
  rates <- c(1e5, 1e6, 5e6)
  expect_true(all(diff(surface_seed_initial(rates, 0.033)) > 0))
})

test_that("invariant 10: seeding-rate conversion round trips exactly", {
  set.seed(42)
  tkw <- runif(500, 0.1, 2000)
  mass <- runif(500, 0.1, 500)
  expect_equal(
    mass_per_ha_from_seeds(seeds_per_ha_from_mass(mass, tkw), tkw),
    mass, tolerance = 1e-12
  )
})

test_that("invariant 11: the two exposure formulations agree", {
  set.seed(7)
  n <- 300
  concentration <- runif(n, 0, 500)
  tkw <- runif(n, 0.5, 1000)
  bw <- runif(n, 5, 2000)
  fir <- food_requirement(bw, 0.398, 0.85)
  diet <- runif(n, 0, 1)
  seed_mass <- seed_mass_from_tkw(tkw)
  dose_per_seed <- treatment_loading(concentration, "mg a.i./kg seed",
                                     tkw)$dose_per_seed_mg
  seeds <- seeds_required_per_day(fir, seed_mass, diet)
  expect_equal(estimated_daily_exposure(concentration, fir, bw, diet),
               daily_ai_intake_dose(seeds, dose_per_seed, bw),
               tolerance = 1e-10)
})

test_that("invariant 12: surface loading equals the combined-half-life form", {
  day <- seq(0, 90, by = 0.5)
  combined <- combined_surface_ai_dt50(14, 10)
  expect_equal(surface_ai_over_time(180, 0.00744, day, 14, 10),
               180 * 0.00744 * 2^(-day / combined), tolerance = 1e-12)
})

test_that("invariant 13: duration above a metric is never negative", {
  set.seed(11)
  dose <- runif(1000, 0, 200)
  metric <- runif(1000, 1, 100)
  out <- duration_above_effect_metric(dose, metric, 10)
  expect_true(all(out >= 0))
  expect_true(all(out[dose <= metric] == 0))
})

test_that("invariant 14: required area times density returns seeds required", {
  set.seed(13)
  seeds <- runif(500, 0, 1e4)
  density <- runif(500, 0.001, 500)
  expect_equal(required_search_area(seeds, density) * density, seeds,
               tolerance = 1e-9)
})

test_that("invariant 15: mass-basis exposure is invariant to seed mass", {
  fir <- 5.078770266809547
  base <- estimated_daily_exposure(300, fir, 20, 1)
  for (tkw in c(1.8, 24.8, 59.5, 1680)) {
    loading <- treatment_loading(300, "mg a.i./kg seed", tkw)
    expect_equal(estimated_daily_exposure(loading$concentration_mg_per_kg_seed,
                                          fir, 20, 1), base)
  }
})

test_that("a per-seed rate does make exposure depend on seed mass", {
  # The complement of invariant 15: when the registered rate is per seed, a
  # heavier seed means a lower concentration and therefore a lower dose.
  fir <- 5.078770266809547
  light <- treatment_loading(0.00744, "mg a.i./seed", 10)
  heavy <- treatment_loading(0.00744, "mg a.i./seed", 100)
  expect_gt(estimated_daily_exposure(light$concentration_mg_per_kg_seed, fir,
                                     20, 1),
            estimated_daily_exposure(heavy$concentration_mg_per_kg_seed, fir,
                                     20, 1))
})
