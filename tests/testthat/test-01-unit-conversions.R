# Unit consistency and round trips. Specification sections 5 and 15.

test_that("seed mass and thousand-seed weight round trip exactly", {
  tkw <- c(0.11, 1.8, 24.8, 59.5, 1680)
  expect_identical(tkw_from_seed_mass(seed_mass_from_tkw(tkw)), tkw)
  expect_equal(seed_mass_from_tkw(24.8), 0.0248)
  expect_equal(tkw_from_seed_mass(0.0248), 24.8)
})

test_that("mass and count seeding rates round trip to machine precision", {
  tkw <- c(2.5, 24.8, 59.5, 300, 1680)
  mass <- c(1.8, 44.64, 279.65, 90, 361.667)
  seeds <- seeds_per_ha_from_mass(mass, tkw)
  expect_equal(mass_per_ha_from_seeds(seeds, tkw), mass, tolerance = 1e-12)

  counts <- c(1.8e6, 4.7e6, 6.4e5, 2.2e7)
  tkw2 <- c(24.8, 59.5, 5.3, 1.8)
  mass2 <- mass_per_ha_from_seeds(counts, tkw2)
  expect_equal(seeds_per_ha_from_mass(mass2, tkw2), counts, tolerance = 1e-12)
})

test_that("the workbook seeding-rate conversion form is reproduced", {
  # Workbook: 1000 * (kg_per_ha / (TKW / 1000)); engine uses kg * 1e6 / TKW.
  workbook_form <- function(kg, tkw) 1000 * (kg / (tkw / 1000))
  expect_equal(seeds_per_ha_from_mass(53.8, 46), workbook_form(53.8, 46))
  expect_equal(seeds_per_ha_from_mass(157, 27), workbook_form(157, 27))
  # Oat lower bound (converted with high TKW) and upper bound (low TKW).
  expect_equal(seeds_per_ha_from_mass(53.8, 46), 1169565.2173913042,
               tolerance = 1e-9)
  expect_equal(seeds_per_ha_from_mass(157, 27), 5814814.8148148144,
               tolerance = 1e-9)
})

test_that("seeds per hectare converts to seeds per square metre", {
  expect_equal(seeds_per_m2(1.8e6), 180)
  expect_equal(seeds_per_m2(c(6e5, 4.7e6)), c(60, 470))
})

test_that("treatment loading handles both registered rate units", {
  per_mass <- treatment_loading(300, "mg a.i./kg seed", 24.8)
  expect_equal(per_mass$concentration_mg_per_kg_seed, 300)
  expect_equal(per_mass$dose_per_seed_mg, 0.00744, tolerance = 1e-12)

  # Workbook form: dose = concentration / (1000000 / TKW).
  expect_equal(per_mass$dose_per_seed_mg, 300 / (1e6 / 24.8), tolerance = 1e-12)

  per_seed <- treatment_loading(0.00744, "mg a.i./seed", 24.8)
  expect_equal(per_seed$dose_per_seed_mg, 0.00744)
  expect_equal(per_seed$concentration_mg_per_kg_seed, 300, tolerance = 1e-9)
})

test_that("treatment loading is vectorised over mixed units", {
  out <- treatment_loading(c(300, 0.00744),
                           c("mg a.i./kg seed", "mg a.i./seed"),
                           c(24.8, 24.8))
  expect_equal(out$concentration_mg_per_kg_seed, c(300, 300), tolerance = 1e-9)
  expect_equal(out$dose_per_seed_mg, c(0.00744, 0.00744), tolerance = 1e-12)
})

test_that("field rate converts mg per kg seed and kg per ha to g a.i. per ha", {
  expect_equal(field_rate_g_ai_per_ha(300, 44.64), 13.392, tolerance = 1e-12)
  expect_equal(field_rate_g_ai_per_ha(300, 279.65), 83.895, tolerance = 1e-12)
  expect_equal(field_rate_g_ai_per_ha(0, 100), 0)
})

test_that("the screening clothianidin conversion uses the stated molar ratio", {
  expect_equal(screening_clothianidin_equivalent(100), 100 * 249.68 / 291.7)
  expect_equal(STBAM_CLOTHIANIDIN_MOLAR_RATIO, 0.8559479, tolerance = 1e-6)
})
