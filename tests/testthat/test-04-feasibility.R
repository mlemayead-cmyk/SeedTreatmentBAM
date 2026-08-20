# Maximum search area and exposure feasibility. Specification section 10.

test_that("available seed within the search area reproduces the audit", {
  # Wheat lower broadcast, small bird: 60 seeds/m2 over a 70 m2 search area.
  expect_equal(available_seed_within_msa(60, 70), 4200)
  expect_equal(available_seed_within_msa(2.843075, 70), 199.015, tolerance = 1e-3)
})

test_that("maximum feasible dietary fraction reproduces the audit", {
  # BSC-CALC-018: 4200 seeds available, 5.07877 g/d, 50 g TKW -> 4134.86 %.
  frac <- maximum_feasible_diet_fraction(60, 70, 5.078770266809547, 0.050)
  expect_equal(frac * 100, 4134.859207, tolerance = 1e-5)

  # BSC-CALC-020: buckwheat upper spring drill, medium bird -> 104.22 %.
  density <- surface_seed_initial(3103448.2758620689, 0.033)
  frac2 <- maximum_feasible_diet_fraction(density, 70, 19.94725189836544, 0.029)
  expect_equal(frac2 * 100, 104.224874, tolerance = 1e-5)
})

test_that("required search area reproduces the workbook crop-sheet cells", {
  # Barley broadcast low density 180 seeds/m2, small bird, 100 % diet.
  # Workbook 1!K20 = 0.474208 (high TKW) and 1!M20 = 1.137717 (low TKW).
  seeds_high_tkw <- seeds_required_per_day(5.078770266809547, 0.0595)
  seeds_low_tkw <- seeds_required_per_day(5.078770266809547, 0.0248)
  expect_equal(seeds_high_tkw, 85.357483475790715, tolerance = 1e-9)
  expect_equal(seeds_low_tkw, 204.78912366167529, tolerance = 1e-9)
  expect_equal(required_search_area(seeds_high_tkw, 180), 0.47420824153217062,
               tolerance = 1e-9)
  expect_equal(required_search_area(seeds_low_tkw, 180), 1.1377173536759739,
               tolerance = 1e-9)
})

test_that("required search area times density returns the seeds required", {
  seeds <- c(85.36, 204.79, 3068.81)
  density <- c(180, 5.94, 16.56)
  expect_equal(required_search_area(seeds, density) * density, seeds,
               tolerance = 1e-12)
})

test_that("boundary behaviour of the search-area calculation", {
  expect_equal(required_search_area(0, 0), 0)
  expect_equal(required_search_area(100, 0), Inf)
  expect_equal(required_search_area(0, 180), 0)
})

test_that("days of availability reproduce the audited durations", {
  # BSC-CALC-019: 4135 % available initially, 14 d surface-seed DT50 -> 75.18 d.
  expect_equal(days_diet_fraction_feasible(41.34859207, 1, 14),
               75.177416, tolerance = 1e-5)

  # BSC-CALC-021: oat upper fall drill, large bird -> 25.17 d.
  density <- surface_seed_initial(5814814.8148148144, 0.092)
  frac <- maximum_feasible_diet_fraction(density, 140, 58.153385883648525, 0.027)
  expect_equal(days_diet_fraction_feasible(frac, 1, 14), 25.171469,
               tolerance = 1e-5)
})

test_that("availability duration uses the surface-seed half-life, not residue", {
  fourteen <- days_diet_fraction_feasible(4, 1, 14)
  ten <- days_diet_fraction_feasible(4, 1, 10)
  expect_equal(fourteen, 28)
  expect_equal(ten, 20)
  expect_false(isTRUE(all.equal(fourteen, ten)))
})

test_that("a fraction that is never obtainable gives zero days", {
  expect_equal(days_diet_fraction_feasible(0.5, 1, 14), 0)
  expect_equal(days_diet_fraction_feasible(1, 1, 14), 0)
  expect_equal(days_diet_fraction_feasible(0, 1, 14), 0)
})

test_that("a scalar half-life does not collapse a vector of fractions", {
  out <- days_diet_fraction_feasible(c(2, 4, 8, 16), 1, 14)
  expect_equal(out, c(14, 28, 42, 56))
})

test_that("feasibility comparison is a plain fraction comparison", {
  expect_true(diet_fraction_is_feasible(0.25, 0.5))
  expect_true(diet_fraction_is_feasible(0.5, 0.5))
  expect_false(diet_fraction_is_feasible(1, 0.5))
  expect_equal(diet_fraction_is_feasible(c(1, 0.5, 0.1), 0.4),
               c(FALSE, FALSE, TRUE))
})
