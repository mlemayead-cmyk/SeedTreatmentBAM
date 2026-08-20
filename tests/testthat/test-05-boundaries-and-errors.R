# Boundary conditions and error handling. Specification sections 15 and 16.

test_that("a zero treatment rate produces zero exposure throughout", {
  loading <- treatment_loading(0, "mg a.i./kg seed", 24.8)
  expect_equal(loading$concentration_mg_per_kg_seed, 0)
  expect_equal(loading$dose_per_seed_mg, 0)
  expect_equal(field_rate_g_ai_per_ha(0, 44.64), 0)
  ede <- estimated_daily_exposure(0, 5.078770266809547, 20, 1)
  expect_equal(ede, 0)
  expect_equal(daily_dose_over_time(ede, 0:30, 10), rep(0, 31))
  expect_equal(risk_quotient(ede, 43.1), 0)
  expect_equal(duration_above_effect_metric(ede, 43.1, 10), 0)
})

test_that("a zero dietary fraction produces zero exposure and zero seeds", {
  expect_equal(estimated_daily_exposure(300, 5.078770266809547, 20, 0), 0)
  expect_equal(seeds_required_per_day(5.078770266809547, 0.0248, 0), 0)
})

test_that("zero surface seed gives zero availability and infinite search area", {
  expect_equal(surface_seed_initial(0, 1), 0)
  expect_equal(available_seed_within_msa(0, 70), 0)
  expect_equal(maximum_feasible_diet_fraction(0, 70, 5.0788, 0.0248), 0)
  expect_equal(required_search_area(100, 0), Inf)
  expect_equal(area_per_surface_seed(0), Inf)
})

test_that("day zero returns the initial condition exactly", {
  expect_equal(surface_seed_over_time(180, 0, 14), 180)
  expect_equal(ai_per_seed_over_time(0.00744, 0, 10), 0.00744)
  expect_equal(daily_dose_over_time(76.18, 0, 10), 76.18)
})

test_that("very long simulations remain finite and monotone", {
  seeds <- surface_seed_over_time(180, 0:3650, 14)
  expect_true(all(is.finite(seeds)))
  expect_true(all(diff(seeds) <= 0))
  expect_lt(seeds[length(seeds)], 1e-50)
})

test_that("extreme seed sizes and seeding rates stay consistent", {
  # Sage at 0.11 g/1000 seeds and chayote at 13460 g/1000 seeds.
  expect_equal(seed_mass_from_tkw(0.11), 0.00011)
  expect_equal(seed_mass_from_tkw(13460), 13.46)
  tiny <- seeds_per_ha_from_mass(1.8, 0.11)
  expect_equal(tiny, 16363636.363636363, tolerance = 1e-6)
  expect_equal(mass_per_ha_from_seeds(tiny, 0.11), 1.8, tolerance = 1e-12)
  huge <- seeds_per_ha_from_mass(96.58896, 13460)
  expect_equal(mass_per_ha_from_seeds(huge, 13460), 96.58896, tolerance = 1e-9)
})

test_that("missing values are rejected rather than silently defaulted", {
  expect_error(estimated_daily_exposure(NA, 5, 20, 1), "missing values")
  expect_error(food_requirement(NA_real_, 0.398, 0.85), "missing values")
  expect_error(surface_seed_initial(c(1e6, NA), 1), "missing values")
  expect_error(check_numeric(NULL, "x"), "required but was not supplied")
})

test_that("negative and out-of-range inputs are rejected", {
  expect_error(estimated_daily_exposure(-1, 5, 20, 1), "at least 0")
  expect_error(estimated_daily_exposure(300, 5, -20, 1),
               "strictly greater than 0")
  expect_error(estimated_daily_exposure(300, 5, 20, 1.5), "at most 1")
  expect_error(estimated_daily_exposure(300, 5, 20, -0.1), "at least 0")
  expect_error(surface_seed_initial(1e6, 1.2), "at most 1")
  expect_error(surface_seed_initial(-1, 1), "at least 0")
  expect_error(seed_mass_from_tkw(0), "strictly greater than 0")
  expect_error(first_order_remaining(-1, 10), "at least 0")
})

test_that("a zero half-life is rejected as undefined", {
  expect_error(first_order_remaining(1, 0), "strictly greater than 0")
  expect_error(surface_seed_over_time(180, 1, 0), "strictly greater than 0")
  expect_error(duration_above_effect_metric(76, 43.1, 0),
               "strictly greater than 0")
})

test_that("a zero effects metric is rejected", {
  expect_error(risk_quotient(76, 0), "strictly greater than 0")
  expect_error(duration_above_effect_metric(76, 0, 10),
               "strictly greater than 0")
})

test_that("unknown units and categories are rejected", {
  expect_error(treatment_loading(300, "mg/kg", 24.8), "Unknown")
  expect_error(treatment_loading(300, "g a.i./kg seed", 24.8), "Unknown")
  expect_error(check_choice("nonsense", "planting_method",
                            STBAM_PLANTING_METHODS), "Unknown")
})

test_that("non-numeric input is rejected with a clear message", {
  expect_error(estimated_daily_exposure("300", 5, 20, 1), "must be numeric")
})

test_that("silent partial recycling is rejected", {
  expect_error(estimated_daily_exposure(c(100, 200, 300), c(5, 6), 20, 1),
               "length 1 or a common length")
  expect_error(surface_seed_over_time(c(1, 2, 3), c(0, 1), 14),
               "length 1 or a common length")
})

test_that("infinite values are rejected except where explicitly permitted", {
  expect_error(estimated_daily_exposure(Inf, 5, 20, 1), "non-finite")
  expect_silent(first_order_remaining(1, Inf))
  expect_silent(duration_above_effect_metric(76, 43.1, Inf))
})

test_that("model errors carry the stbam condition class", {
  err <- tryCatch(risk_quotient(1, 0), error = function(e) e)
  expect_s3_class(err, "stbam_error")
})
