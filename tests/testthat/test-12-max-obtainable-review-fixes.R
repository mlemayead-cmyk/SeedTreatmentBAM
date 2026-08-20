# Regression tests for confirmed defects found by the independent adversarial
# review (docs/max_obtainable_exposure_review.md), fixed in this session.
# Kept as a separate file from test-10/test-11 to avoid churn on files under
# concurrent edit elsewhere in the project.

baseline <- load_baseline()
params <- parameter_set(baseline)

test_that("mammal footnote reports the accessible pool actually used, not just the surface density (review check 6)", {
  # Independent review finding: for SURFACE_PLUS_BURIED receptors (all
  # mammals), the footnote previously stated initial_surface_seeds_per_m2
  # (e.g. 15.5 seeds/m2) while the maximum-obtainable curve was actually
  # built on the full sown density (e.g. 470 seeds/m2) -- a 30x
  # discrepancy that defeated the feature's self-contained-interpretation
  # requirement.
  scen <- build_scenario_inputs(params, crops = "Barley",
                                workbooks = "small_cereals",
                                rate_levels = "high",
                                planting_methods = "drill_spring")
  one <- scen[scen$seeding_rate_bound == "high" &
                scen$seed_mass_bound == "high_tkw", ]
  metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "mammal")
  receptors <- resolve_receptors(params, "mammal_small")
  tc <- build_daily_timecourse(params, one, receptors, metrics,
                               diet_fractions = 1, days = 0)
  row <- tc[tc$metric_id == "mammal_chronic_screening", ]
  expect_equal(row$accessible_pool_basis, "SURFACE_PLUS_BURIED")
  expect_true(row$accessible_seeds_per_m2_t > 10 * row$initial_surface_seeds_per_m2)

  meta <- build_figure_metadata(row, metrics, params)
  expect_equal(meta$accessible_pool_basis, "SURFACE_PLUS_BURIED")
  expect_equal(meta$accessible_seeds_per_m2, row$accessible_seeds_per_m2_t)

  footnote <- format_figure_footnotes(meta, detail = "full")
  # The footnote must state the actual accessible-pool figure, not only the
  # (much smaller) surface figure, and must say so using the surface value
  # too so a reader can see both and understand why they differ.
  expect_true(grepl(fmt_sig(row$accessible_seeds_per_m2_t), footnote,
                    fixed = TRUE))
  expect_true(grepl(fmt_sig(row$initial_surface_seeds_per_m2), footnote,
                    fixed = TRUE))
  expect_true(grepl("ASSUMPTION-020", footnote, fixed = TRUE))
  expect_true(grepl("FULL sown density", footnote, fixed = TRUE))
})

test_that("bird footnote is unaffected by the mammal pool-reporting fix (review check 6, bird case still PASS)", {
  scen <- build_scenario_inputs(params, crops = "Barley",
                                workbooks = "small_cereals",
                                rate_levels = "high",
                                planting_methods = "broadcast")
  one <- scen[scen$seeding_rate_bound == "low" & scen$seed_mass_bound == "low_tkw", ]
  metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "bird")
  receptors <- resolve_receptors(params, "bird_small")
  tc <- build_daily_timecourse(params, one, receptors, metrics,
                               diet_fractions = 1, days = 0)
  row <- tc[tc$metric_id == "bird_acute_screening", ]
  expect_equal(row$accessible_pool_basis, "SURFACE_SEED_ONLY")
  meta <- build_figure_metadata(row, metrics, params)
  footnote <- format_figure_footnotes(meta, detail = "full")
  expect_false(grepl("FULL sown density", footnote, fixed = TRUE))
  expect_true(grepl("180 seeds/m2", footnote, fixed = TRUE))
})

test_that("an overridden msa_m2 is reported honestly rather than mis-attributed to MAIN-P000209 (review finding A2)", {
  scen <- build_scenario_inputs(params, crops = "Barley",
                                workbooks = "small_cereals",
                                rate_levels = "high",
                                planting_methods = "broadcast")
  one <- scen[scen$seeding_rate_bound == "low" & scen$seed_mass_bound == "low_tkw", ]
  metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "mammal")
  overridden <- set_override(params, "msa_m2", 0.5, scope = "mammal_small")
  receptors <- resolve_receptors(overridden, "mammal_small")
  tc <- build_daily_timecourse(overridden, one, receptors, metrics,
                               diet_fractions = 1, days = 0)
  acute <- tc[tc$duration_class == "acute", ]
  chronic <- tc[tc$duration_class == "chronic", ]
  # The override collapses the short/long distinction -- both now read 0.5.
  expect_equal(acute$max_obtainable_msa_m2, 0.5)
  expect_equal(chronic$max_obtainable_msa_m2, 0.5)

  meta <- build_figure_metadata(chronic, metrics, overridden)
  expect_true(meta$msa_is_overridden)
  footnote <- format_figure_footnotes(meta, detail = "full")
  expect_true(grepl("USER OVERRIDE", footnote, fixed = TRUE))
  # Collapse wrapped whitespace/newlines before checking the longer phrase,
  # since format_figure_footnotes() wraps each line to a fixed width and may
  # insert a line break in the middle of it.
  expect_true(grepl("does not apply to an overridden",
                    gsub("\\s+", " ", footnote), fixed = TRUE))
})

test_that("an msa_m2 override with no baseline scope leaves the policy attribution intact (control case)", {
  scen <- build_scenario_inputs(params, crops = "Barley",
                                workbooks = "small_cereals",
                                rate_levels = "high",
                                planting_methods = "broadcast")
  one <- scen[scen$seeding_rate_bound == "low" & scen$seed_mass_bound == "low_tkw", ]
  metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "bird")
  receptors <- resolve_receptors(params, "bird_small")
  tc <- build_daily_timecourse(params, one, receptors, metrics,
                               diet_fractions = 1, days = 0)
  row <- tc[tc$metric_id == "bird_acute_screening", ]
  meta <- build_figure_metadata(row, metrics, params)
  expect_false(meta$msa_is_overridden)
  footnote <- format_figure_footnotes(meta, detail = "full")
  expect_true(grepl("MAIN-P000209", footnote, fixed = TRUE))
  expect_false(grepl("USER OVERRIDE", footnote, fixed = TRUE))
})

test_that("plot_max_obtainable_exposure rejects mixed scenario/receptor/metric input (review finding A6)", {
  scen <- build_scenario_inputs(params, crops = "Barley",
                                workbooks = "small_cereals",
                                rate_levels = "high",
                                planting_methods = "broadcast")
  one <- scen[scen$seeding_rate_bound == "low" & scen$seed_mass_bound == "low_tkw", ]
  metrics <- resolve_effects_metrics(params, "SCREENING", taxa = "bird")
  receptors <- resolve_receptors(params, "bird_small")
  tc <- build_daily_timecourse(params, one, receptors, metrics,
                               diet_fractions = 1, days = 0)
  meta <- build_figure_metadata(tc[1, ], metrics, params)
  expect_error(plot_max_obtainable_exposure(tc, meta),
              "requires a single")
})
