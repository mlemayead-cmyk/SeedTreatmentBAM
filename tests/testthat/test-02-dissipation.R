# Surface-seed disappearance and residue dissipation as SEPARATE processes.
# Specification section 7.

test_that("first-order decline halves at each half-life", {
  expect_equal(first_order_remaining(0, 10), 1)
  expect_equal(first_order_remaining(10, 10), 0.5)
  expect_equal(first_order_remaining(20, 10), 0.25)
  expect_equal(first_order_remaining(14, 14), 0.5)
})

test_that("a scalar half-life does not collapse a vector of days", {
  # Regression test: base ifelse() returns the shape of its test, which
  # silently produced a constant column for every day when the half-life was
  # a single value.
  out <- first_order_remaining(0:5, 10)
  expect_length(out, 6L)
  expect_false(any(duplicated(out)))
  expect_equal(out, 2^(-(0:5) / 10))
})

test_that("an infinite half-life means no dissipation", {
  expect_equal(first_order_remaining(0:30, Inf), rep(1, 31))
  expect_equal(ai_per_seed_over_time(0.00744, 0:10, Inf), rep(0.00744, 11))
})

test_that("surface seed density at sowing follows the planting method", {
  expect_equal(surface_seed_initial(1.8e6, 1.000), 180)
  expect_equal(surface_seed_initial(1.8e6, 0.033), 5.94)
  expect_equal(surface_seed_initial(1.8e6, 0.092), 16.56, tolerance = 1e-12)
  expect_equal(surface_seed_initial(4.7e6, 1.000), 470)
  expect_equal(surface_seed_initial(1.8e6, 0.005), 0.9)
})

test_that("mean area per surface seed is the reciprocal of density", {
  expect_equal(area_per_surface_seed(180), 1 / 180)
  expect_equal(area_per_surface_seed(470), 1 / 470)
  expect_equal(area_per_surface_seed(0), Inf)
})

test_that("surface seed is non-increasing in time", {
  seeds <- surface_seed_over_time(180, 0:60, 14)
  expect_true(all(diff(seeds) <= 0))
  expect_equal(seeds[1], 180)
  expect_equal(seeds[15], 90)
})

test_that("residue per seed is non-increasing in time", {
  ai <- ai_per_seed_over_time(0.00744, 0:60, 10)
  expect_true(all(diff(ai) <= 0))
  expect_equal(ai[1], 0.00744)
  expect_equal(ai[11], 0.00372)
})

test_that("the two processes use their own half-lives and are independent", {
  seeds <- surface_seed_over_time(180, 10, 14)
  ai <- ai_per_seed_over_time(0.00744, 10, 10)
  expect_equal(seeds, 180 * 2^(-10 / 14))
  expect_equal(ai, 0.00744 * 0.5)
  # Changing one half-life must not change the other process.
  expect_equal(surface_seed_over_time(180, 10, 14),
               surface_seed_over_time(180, 10, 14))
  expect_false(isTRUE(all.equal(ai_per_seed_over_time(0.00744, 10, 10),
                                ai_per_seed_over_time(0.00744, 10, 14))))
})

test_that("surface loading equals the product of the two processes", {
  day <- 0:40
  product <- surface_ai_over_time(180, 0.00744, day, 14, 10)
  expect_equal(product,
               surface_seed_over_time(180, day, 14) *
                 ai_per_seed_over_time(0.00744, day, 10))

  # And equals the combined-half-life form.
  combined <- combined_surface_ai_dt50(14, 10)
  expect_equal(combined, 1 / (1 / 14 + 1 / 10))
  expect_equal(product, 180 * 0.00744 * 2^(-day / combined), tolerance = 1e-12)
})

test_that("combined half-life is shorter than either component", {
  combined <- combined_surface_ai_dt50(14, 10)
  expect_lt(combined, 10)
  expect_lt(combined, 14)
  expect_equal(combined, 5.833333, tolerance = 1e-5)
})
