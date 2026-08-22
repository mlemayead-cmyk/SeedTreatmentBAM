# Phase 2: migration (ADR-015) + evaluation-inputs -> engine-parameter-set
# adapter (migration_plan.md §3 step 4). Invariant I11 (migration reproduces
# scenario_inputs/scenario_summary identical to the pre-migration engine
# output) and the 9-point migration-equivalence gate (migration_plan.md §4).
#
# Uses the same isolated temp-project-root fixture convention as Phase 1's
# tests (test-14-phase1-evaluations.R's stbam_use_fixture_project_root()) --
# migration only reads data/reference/, never writes to it, but every test
# below still runs against an isolated copy, never the real project root, so
# concurrent test runs (and any stray real evaluations/ directory) cannot
# interact with these tests. testthat sources each test-*.R file into its
# own environment, so this helper (identical to test-14's) is redefined
# here rather than shared, to avoid coupling the two test files together.

#' Point `stbam_project_root()` at a temp dir with its own copy of
#' `data/reference/*.csv`, scoped to the calling test_that() block.
#' @noRd
stbam_use_fixture_project_root <- function() {
  root <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(root, "data", "reference"), recursive = TRUE)
  real_ref <- file.path(stbam_project_root(), "data", "reference")
  for (f in list.files(real_ref, pattern = "[.]csv$")) {
    file.copy(file.path(real_ref, f), file.path(root, "data", "reference", f))
  }
  withr::local_options(list(stbam.project_root = root), .local_envir = parent.frame())
  root
}

# ---------------------------------------------------------------------------
# Independent ground truth for the hard-coded count assertions (gate point
# 3). These numbers are NOT derived from migrate_to_evaluation()'s own
# output -- they are computed here directly from the raw reference CSVs
# using a separate, minimal method-availability calculation, so a bug that
# made migration and this test agree with each other but not with the real
# data would still be caught.
# ---------------------------------------------------------------------------

#' @noRd
stbam_ground_truth_available_methods <- function(crop_row) {
  m <- character()
  if (isTRUE(crop_row$broadcast_seeded)) m <- c(m, "broadcast")
  if (isTRUE(crop_row$drill_seeded) && isTRUE(crop_row$spring_seeded)) {
    m <- c(m, "drill_spring")
  }
  if (isTRUE(crop_row$drill_seeded) && isTRUE(crop_row$fall_seeded)) {
    m <- c(m, "drill_fall")
  }
  if (isTRUE(crop_row$precision_planted)) m <- c(m, "precision")
  m
}

test_that("ground truth: real reference data has the documented row counts", {
  scenarios <- readr::read_csv(
    file.path(stbam_project_root(), "data", "reference", "scenario_definitions.csv"),
    show_col_types = FALSE
  )
  crops <- readr::read_csv(
    file.path(stbam_project_root(), "data", "reference", "crop_seeding_parameters.csv"),
    show_col_types = FALSE
  )
  expect_equal(nrow(scenarios), 157L)
  expect_equal(nrow(crops), 85L)
  expect_equal(length(unique(scenarios$crop)), 42L)
  expect_equal(
    length(unique(scenarios$crop[scenarios$workbook == "small_cereals"])), 11L
  )

  expected_use_pattern_rows <- 0L
  for (i in seq_len(nrow(scenarios))) {
    crop_row <- crops[crops$crop == scenarios$crop[[i]], ][1, ]
    expected_use_pattern_rows <- expected_use_pattern_rows +
      length(stbam_ground_truth_available_methods(crop_row))
  }
  expect_equal(expected_use_pattern_rows, 364L)
})

# ---------------------------------------------------------------------------
# Unit test: scenario_definitions -> use_patterns transformation
# ---------------------------------------------------------------------------

#' @noRd
stbam_tiny_crops <- function() {
  tibble::tibble(
    crop = c("Barley", "Canola"),
    tkw_low_g_per_1000 = c(38.0, 3.5), tkw_high_g_per_1000 = c(45.0, 5.5),
    seeding_rate_low_seeds_per_ha_direct = c(NA_real_, NA_real_),
    seeding_rate_high_seeds_per_ha_direct = c(NA_real_, NA_real_),
    seeding_rate_low_kg_per_ha_low_tkw = c(90.0, 4.0),
    seeding_rate_low_kg_per_ha_high_tkw = c(100.0, 5.0),
    seeding_rate_high_kg_per_ha_low_tkw = c(120.0, 6.0),
    seeding_rate_high_kg_per_ha_high_tkw = c(130.0, 7.0),
    seeds_per_ha_low = c(2000000, 5000000), seeds_per_ha_high = c(2500000, 6000000),
    seeds_per_ha_low_basis = "CONVERTED_FROM_MASS",
    seeds_per_ha_high_basis = "CONVERTED_FROM_MASS",
    spring_seeded = c(TRUE, TRUE), fall_seeded = c(TRUE, FALSE),
    broadcast_seeded = c(TRUE, FALSE), drill_seeded = c(TRUE, TRUE),
    precision_planted = c(FALSE, TRUE),
    source = "Test fixture", status = "ASSESSMENT_DEFAULT"
  )
}

test_that("stbam_transform_use_patterns explodes a multi-planting-method use into shared-use_id rows", {
  scenarios <- tibble::tibble(
    workbook = "small_cereals", crop = "Barley", rate_level = "high",
    application_rate = 300, application_rate_unit = "mg a.i./kg seed"
  )
  out <- stbam_transform_use_patterns(scenarios, stbam_tiny_crops())

  # Barley: broadcast_seeded, drill_seeded x (spring_seeded, fall_seeded) ->
  # broadcast, drill_spring, drill_fall (3 rows), all sharing one use_id.
  expect_equal(nrow(out), 3L)
  expect_equal(length(unique(out$use_id)), 1L)
  expect_setequal(out$planting_method, c("broadcast", "drill_spring", "drill_fall"))
  expect_true(all(out$crop == "Barley"))
  expect_true(all(out$rate_value == 300))
  expect_true(all(out$rate_unit == "mg a.i./kg seed"))
})

test_that("stbam_transform_use_patterns keeps distinct use_ids for the same rate_level at different rates (legume mg/kg vs mg/seed case)", {
  scenarios <- tibble::tibble(
    workbook = c("legumes_deep", "legumes_deep"),
    crop = c("Canola", "Canola"),
    rate_level = c("high", "high"),
    application_rate = c(300, 0.045),
    application_rate_unit = c("mg a.i./kg seed", "mg a.i./seed")
  )
  out <- stbam_transform_use_patterns(scenarios, stbam_tiny_crops())

  # Canola: drill_seeded + spring_seeded -> drill_spring; precision_planted
  # -> precision. 2 methods x 2 distinct rate rows = 4 rows, 2 distinct use_ids.
  expect_equal(nrow(out), 4L)
  expect_equal(length(unique(out$use_id)), 2L)
  expect_setequal(out$planting_method, c("drill_spring", "precision"))
})

test_that("stbam_transform_use_patterns aborts on a genuine workbook/crop/rate_level/rate/unit duplicate", {
  scenarios <- tibble::tibble(
    workbook = c("small_cereals", "small_cereals"),
    crop = c("Barley", "Barley"), rate_level = c("high", "high"),
    application_rate = c(300, 300),
    application_rate_unit = c("mg a.i./kg seed", "mg a.i./kg seed")
  )
  expect_error(stbam_transform_use_patterns(scenarios, stbam_tiny_crops()),
              "duplicate")
})

test_that("stbam_transform_use_patterns aborts if a scenario references an unknown crop", {
  scenarios <- tibble::tibble(
    workbook = "small_cereals", crop = "Nonexistent Crop", rate_level = "high",
    application_rate = 300, application_rate_unit = "mg a.i./kg seed"
  )
  expect_error(stbam_transform_use_patterns(scenarios, stbam_tiny_crops()),
              "absent from the seeding-set data")
})

# ---------------------------------------------------------------------------
# Unit test: STBAM_WORKBOOK_TO_CROP_FAMILY -> reporting_sets extraction
# ---------------------------------------------------------------------------

test_that("stbam_extract_crop_family_reporting_set reproduces STBAM_WORKBOOK_TO_CROP_FAMILY unchanged", {
  scenarios <- tibble::tibble(
    workbook = c("small_cereals", "small_cereals", "canola"),
    crop = c("Barley", "Rye", "Canola")
  )
  out <- stbam_extract_crop_family_reporting_set(scenarios)

  expect_setequal(out$crop, c("Barley", "Rye", "Canola"))
  expect_equal(out$group_label[out$crop == "Barley"], "Small Cereals")
  expect_equal(out$group_label[out$crop == "Rye"], "Small Cereals")
  expect_equal(out$group_label[out$crop == "Canola"], "Canola/Mustard")
  # Crop-only (I7): no non-crop column present.
  expect_setequal(names(out), c("crop", "group_label", "display_order"))
})

test_that("stbam_extract_crop_family_reporting_set validates against its own schema (I7)", {
  scenarios <- tibble::tibble(workbook = "small_cereals", crop = "Barley")
  out <- stbam_extract_crop_family_reporting_set(scenarios)
  result <- validate_table(out, stbam_schema_reporting_sets())
  expect_true(result$valid)
})

test_that("stbam_extract_crop_family_reporting_set aborts on an unmapped workbook", {
  scenarios <- tibble::tibble(workbook = "unknown_workbook", crop = "X")
  expect_error(stbam_extract_crop_family_reporting_set(scenarios), "no mapping")
})

# ---------------------------------------------------------------------------
# Unit test: tier-1 provenance table
# ---------------------------------------------------------------------------

test_that("stbam_tier1_provenance_table includes all 6 workbooks plus the Table 162 document, path+hash only", {
  source_manifest <- readr::read_csv(
    file.path(stbam_project_root(), "data", "reference", "source_manifest.csv"),
    show_col_types = FALSE
  )
  out <- stbam_tier1_provenance_table(source_manifest)

  expect_equal(nrow(out), 7L)
  expect_true("table162_document" %in% out$workbook_key)
  expect_setequal(out$workbook_key, c(source_manifest$workbook_key, "table162_document"))
  # Hashes for the 6 workbooks are carried unchanged from source_manifest.csv.
  for (wb in source_manifest$workbook_key) {
    expect_equal(out$sha256[out$workbook_key == wb],
                source_manifest$sha256[source_manifest$workbook_key == wb])
  }
  expect_equal(
    out$sha256[out$workbook_key == "table162_document"],
    "ea76adfa0044db808867d880325a1932b891a1d72566f4a8c7b8752a0a36fb6a"
  )
  expect_false(any(out$copied_into_evaluation))
})

# ---------------------------------------------------------------------------
# Full migration: real project data (fixture-isolated) -> evaluation
# ---------------------------------------------------------------------------

test_that("migrate_to_evaluation produces a complete evaluation from the real reference data", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")

  path <- migrate_to_evaluation(evaluations_root, "thiamethoxam_bam_2026")
  expect_true(dir.exists(path))

  # Gate point 4 support: every named-set category is populated.
  for (category in names(STBAM_SET_CATEGORIES)) {
    manifest <- list_named_sets(path, category)
    expect_true(nrow(manifest) >= 1L, info = category)
  }

  use_patterns <- read_use_patterns(path)
  expect_equal(nrow(use_patterns), 364L)  # gate point 3: hard-coded expected count
  expect_equal(length(unique(use_patterns$crop)), 42L)

  crop_family <- read_named_set(path, "reporting_sets", "crop_family")
  expect_equal(length(unique(crop_family$crop)), 42L)  # gate point 6
})

test_that("migrate_to_evaluation copies all 6 tier-3 provenance files, byte-identical (gate point 4)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- migrate_to_evaluation(evaluations_root, "Eval_Prov")

  for (file_name in STBAM_REFERENCE_PROVENANCE_FILES) {
    migrated <- file.path(path, "inputs", "reference", file_name)
    original <- file.path(fixture, "data", "reference", file_name)
    expect_true(file.exists(migrated), info = file_name)
    expect_identical(
      tools::md5sum(migrated)[[1]], tools::md5sum(original)[[1]],
      info = paste("byte-identical:", file_name)
    )
  }
  expect_equal(length(STBAM_REFERENCE_PROVENANCE_FILES), 6L)
})

test_that("migrate_to_evaluation performs a lossless named-set copy (gate point 5)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- migrate_to_evaluation(evaluations_root, "Eval_Lossless")

  checks <- list(
    seeding_sets = "crop_seeding_parameters.csv",
    planting_method_sets = "planting_method_parameters.csv",
    receptor_sets = "receptor_parameters.csv",
    effects_sets = "effects_metrics.csv",
    fate_sets = "dissipation_parameters.csv"
  )
  for (category in names(checks)) {
    original <- readr::read_csv(
      file.path(fixture, "data", "reference", checks[[category]]),
      show_col_types = FALSE
    )
    migrated <- read_named_set(path, category, "default")
    hash_original <- stbam_content_hash(list(x = original))
    hash_migrated <- stbam_content_hash(list(x = migrated))
    expect_identical(hash_migrated, hash_original, info = category)
  }
})

test_that("migrate_to_evaluation does not truncate crops (positive-control regression guard for the new raw layer, gate point 7; distinct from the legacy Shiny-layer R7 defect, which lives in a different, unrelated layer)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- migrate_to_evaluation(evaluations_root, "Eval_NoTrunc")

  ps <- build_parameter_set_from_evaluation(path)
  scenario_inputs <- build_scenario_inputs(ps, workbooks = "small_cereals")
  expect_equal(length(unique(scenario_inputs$crop)), 11L)

  scenario_inputs_all <- build_scenario_inputs(ps)
  expect_equal(length(unique(scenario_inputs_all$crop)), 42L)
})

test_that("migration is re-runnable: two independent runs produce byte-identical inputs/ (gate point 9)", {
  fixture <- stbam_use_fixture_project_root()

  root_a <- file.path(fixture, "evaluations_a")
  root_b <- file.path(fixture, "evaluations_b")
  path_a <- migrate_to_evaluation(root_a, "thiamethoxam_bam_2026")
  path_b <- migrate_to_evaluation(root_b, "thiamethoxam_bam_2026")

  files_a <- sort(list.files(file.path(path_a, "inputs"), recursive = TRUE))
  files_b <- sort(list.files(file.path(path_b, "inputs"), recursive = TRUE))
  expect_identical(files_a, files_b)

  for (f in files_a) {
    hash_a <- tools::md5sum(file.path(path_a, "inputs", f))[[1]]
    hash_b <- tools::md5sum(file.path(path_b, "inputs", f))[[1]]
    expect_identical(hash_a, hash_b, info = f)
  }
})

test_that("re-running migration with the SAME evaluation name fails cleanly, not silently overwriting", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  migrate_to_evaluation(evaluations_root, "Eval_Once")
  expect_error(migrate_to_evaluation(evaluations_root, "Eval_Once"), "already exists")
})

# ---------------------------------------------------------------------------
# Migration-equivalence gate points 1-2: exact scenario_inputs/scenario_summary
# match against a freshly-computed current-baseline canonical output (never
# a stored value -- avoids the AUD-099 circularity failure mode).
# ---------------------------------------------------------------------------

test_that("the adapter's scenario_inputs is exactly equivalent to the pre-migration engine output (I11, gate point 1)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- migrate_to_evaluation(evaluations_root, "thiamethoxam_bam_2026")

  migrated_ps <- build_parameter_set_from_evaluation(path)
  migrated_si <- build_scenario_inputs(migrated_ps)

  current_baseline <- load_baseline()
  current_ps <- parameter_set(current_baseline, name = "current")
  current_si <- build_scenario_inputs(current_ps)

  expect_equal(nrow(migrated_si), nrow(current_si))

  drop_label <- function(df) df[, setdiff(names(df), "parameter_set")]
  order_by_id <- function(df) df[order(df$scenario_id), , drop = FALSE]

  a <- order_by_id(drop_label(migrated_si))
  b <- order_by_id(drop_label(current_si))
  expect_equal(as.data.frame(a), as.data.frame(b))

  # Explicit column-set check: adapter must not add, drop or rename columns.
  expect_setequal(names(migrated_si), names(current_si))
})

test_that("the adapter's scenario_summary is exactly equivalent to the pre-migration engine output (I11, gate point 2)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- migrate_to_evaluation(evaluations_root, "thiamethoxam_bam_2026")

  migrated_ps <- build_parameter_set_from_evaluation(path)
  migrated_si <- build_scenario_inputs(migrated_ps)
  migrated_ss <- build_scenario_summary(migrated_ps, migrated_si)

  current_baseline <- load_baseline()
  current_ps <- parameter_set(current_baseline, name = "current")
  current_si <- build_scenario_inputs(current_ps)
  current_ss <- build_scenario_summary(current_ps, current_si)

  expect_equal(nrow(migrated_ss), nrow(current_ss))

  drop_label <- function(df) df[, setdiff(names(df), "parameter_set")]
  key_cols <- c("scenario_id", "receptor_id", "metric_id", "diet_fraction")
  order_by_key <- function(df) df[do.call(order, df[key_cols]), , drop = FALSE]

  a <- order_by_key(drop_label(migrated_ss))
  b <- order_by_key(drop_label(current_ss))
  expect_equal(as.data.frame(a), as.data.frame(b))
  expect_setequal(names(migrated_ss), names(current_ss))
})

# ---------------------------------------------------------------------------
# Adapter unit tests, independent of the full migration script (a
# hand-constructed minimal evaluation, per migration_plan.md §5)
# ---------------------------------------------------------------------------

#' @noRd
stbam_write_minimal_evaluation <- function(evaluations_root, name = "Mini") {
  path <- create_evaluation(evaluations_root, name)

  seeding <- tibble::tibble(
    crop = "Barley", tkw_low_g_per_1000 = 40, tkw_high_g_per_1000 = 40,
    seeding_rate_low_seeds_per_ha_direct = NA_real_,
    seeding_rate_high_seeds_per_ha_direct = NA_real_,
    seeding_rate_low_kg_per_ha_low_tkw = 100, seeding_rate_low_kg_per_ha_high_tkw = 100,
    seeding_rate_high_kg_per_ha_low_tkw = 100, seeding_rate_high_kg_per_ha_high_tkw = 100,
    seeds_per_ha_low = 2500000, seeds_per_ha_high = 2500000,
    seeds_per_ha_low_basis = "CONVERTED_FROM_MASS",
    seeds_per_ha_high_basis = "CONVERTED_FROM_MASS",
    spring_seeded = TRUE, fall_seeded = FALSE, broadcast_seeded = TRUE,
    drill_seeded = FALSE, precision_planted = FALSE,
    source = "hand", status = "ASSESSMENT_DEFAULT"
  )
  write_named_set(path, "seeding_sets", "default", seeding,
                  tibble::tibble(set_id = "default", set_name = "default",
                                description = "", source = "", date_or_version = "",
                                status = "active", notes = ""))

  planting <- tibble::tibble(
    planting_method_label = "Broadcast", planting_method = "broadcast",
    surface_seed_fraction = 1.0, source = NA_character_, status = "ASSESSMENT_DEFAULT"
  )
  write_named_set(path, "planting_method_sets", "default", planting,
                  tibble::tibble(set_id = "default", set_name = "default",
                                description = "", source = "", date_or_version = "",
                                status = "active", notes = ""))

  receptors <- tibble::tibble(
    receptor_id = "bird_small", taxon = "bird", size_class = "small",
    body_weight_g = 20, fir_regression_name = "bird_small",
    fir_coefficient_a = 0.398, fir_exponent_b = 0.85,
    food_intake_g_dw_per_day = 5, msa_short_term_m2 = 100, msa_long_term_m2 = 300,
    surface_seed_only = TRUE, source = "hand", status = "ASSESSMENT_DEFAULT"
  )
  write_named_set(path, "receptor_sets", "default", receptors,
                  tibble::tibble(set_id = "default", set_name = "default",
                                description = "", source = "", date_or_version = "",
                                status = "active", notes = ""))

  effects <- tibble::tibble(
    metric_id = "bird_acute_screening", active_ingredient = "thiamethoxam",
    taxon = "bird", duration_class = "acute", metric_role = "SCREENING",
    endpoint_description = "test", endpoint_value = 43.1, uncertainty_factor = 1,
    effects_metric = 43.1, unit = "mg a.i./kg bw/d", source = "hand",
    status = "ASSESSMENT_DEFAULT"
  )
  write_named_set(path, "effects_sets", "default", effects,
                  tibble::tibble(set_id = "default", set_name = "default",
                                description = "", source = "", date_or_version = "",
                                status = "active", notes = ""))

  fate <- tibble::tibble(
    parameter = c("residue_dt50_days", "surface_seed_dt50_days"),
    value = c(10, 14), unit = "days", description = "test",
    source = "hand", status = "ASSESSMENT_DEFAULT"
  )
  write_named_set(path, "fate_sets", "default", fate,
                  tibble::tibble(set_id = "default", set_name = "default",
                                description = "", source = "", date_or_version = "",
                                status = "active", notes = ""))

  use_patterns <- tibble::tibble(
    use_id = "small_cereals|Barley|high|300|mg a.i./kg seed", crop = "Barley",
    rate_value = 300, rate_unit = "mg a.i./kg seed", rate_level = "high",
    planting_method = "broadcast", workbook = "small_cereals",
    product_identifier = NA_character_, region = NA_character_,
    target_pest = NA_character_, notes = NA_character_
  )
  write_use_patterns(path, use_patterns)

  path
}

test_that("the adapter builds a working parameter set from a hand-constructed minimal evaluation, matching a hand-built baseline exactly", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- stbam_write_minimal_evaluation(evaluations_root)

  ps <- build_parameter_set_from_evaluation(path, name = "mini")
  si <- build_scenario_inputs(ps)
  # 1 crop x 1 method x 2 seeding-rate bounds x 2 seed-mass bounds -- the
  # engine's documented 2x2 grid (AUD-027), not a 1-dimensional bound.
  expect_equal(nrow(si), 4L)
  expect_true(all(si$crop == "Barley"))
  expect_true(all(si$planting_method == "broadcast"))

  # Hand-built baseline bypassing all named-set I/O -- the adapter's real
  # risk surface is the CSV/named-set reading and reassembly, not the
  # calculation itself (already independently audited elsewhere), so this
  # comparison isolates that boundary.
  hand_baseline <- structure(list(
    crops = read_named_set(path, "seeding_sets", "default"),
    planting_methods = read_named_set(path, "planting_method_sets", "default"),
    receptors = read_named_set(path, "receptor_sets", "default"),
    fir_regressions = tibble::tibble(),
    effects_metrics = read_named_set(path, "effects_sets", "default"),
    dissipation = read_named_set(path, "fate_sets", "default"),
    scenarios = tibble::tibble(workbook = "small_cereals", crop = "Barley",
                              rate_level = "high", application_rate = 300,
                              application_rate_unit = "mg a.i./kg seed"),
    source_manifest = tibble::tibble()
  ), class = c("stbam_baseline", "list"))
  hand_ps <- parameter_set(hand_baseline, name = "hand")
  hand_si <- build_scenario_inputs(hand_ps)

  order_key <- c("seeding_rate_bound", "seed_mass_bound")
  si_o <- si[do.call(order, si[order_key]), ]
  hand_si_o <- hand_si[do.call(order, hand_si[order_key]), ]

  expect_equal(si_o$dose_per_seed_mg, hand_si_o$dose_per_seed_mg)
  expect_equal(si_o$field_rate_g_ai_per_ha, hand_si_o$field_rate_g_ai_per_ha)
  expect_equal(si_o$initial_surface_seeds_per_m2, hand_si_o$initial_surface_seeds_per_m2)
  expect_equal(si_o$seeds_per_ha, hand_si_o$seeds_per_ha)

  ss <- build_scenario_summary(ps, si)
  # 4 bound combinations x 6 default dietary fractions (STBAM_DIET_FRACTIONS).
  expect_equal(nrow(ss), 24L)
  # screening_rq (fixed at the 100%-diet exposure) equals initial_rq (at the
  # row's own diet_fraction) exactly where diet_fraction == 1 -- a
  # hand-verifiable identity that holds regardless of grid size, unlike
  # comparing across every diet fraction.
  at_full_diet <- ss$diet_fraction == 1
  expect_true(any(at_full_diet))
  expect_equal(ss$screening_rq[at_full_diet], ss$initial_rq[at_full_diet])
})

test_that("the adapter fails clearly on a missing required named-set category (not a silent legacy fallback)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- create_evaluation(evaluations_root, "Eval_Missing")
  # A freshly-created evaluation has a "default" set in every populated
  # category already (ADR-003) -- delete one to simulate a genuinely
  # incomplete evaluation.
  delete_named_set(path, "fate_sets", "default")

  expect_error(build_baseline_from_evaluation(path), "no `fate_sets` set")
})

test_that("the adapter fails clearly on an unresolved requested set_id", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- create_evaluation(evaluations_root, "Eval_BadSetId")

  expect_error(
    build_baseline_from_evaluation(path, set_ids = list(seeding_sets = "nonexistent")),
    "no `seeding_sets` set with set_id `nonexistent`"
  )
})

test_that("the adapter fails clearly on an empty use_patterns.csv rather than silently returning nothing", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- create_evaluation(evaluations_root, "Eval_EmptyUses")  # use_patterns.csv starts empty

  expect_error(build_baseline_from_evaluation(path), "empty use_patterns.csv")
})

test_that("the adapter fails clearly when use_patterns.csv references an unresolved crop", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- stbam_write_minimal_evaluation(evaluations_root, "Eval_BadCrop")

  bad_uses <- read_use_patterns(path)
  bad_uses$crop <- "Nonexistent Crop"
  # Bypass write_use_patterns()'s own referential-integrity check (which
  # would itself catch this) by writing the CSV directly, simulating a
  # hand-edited or externally-produced file reaching the adapter.
  readr::write_csv(bad_uses, stbam_use_patterns_path(path))

  expect_error(build_baseline_from_evaluation(path), "absent from the selected seeding set")
})

test_that("the adapter fails clearly when use_patterns.csv references an unresolved planting method", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- stbam_write_minimal_evaluation(evaluations_root, "Eval_BadMethod")

  bad_uses <- read_use_patterns(path)
  bad_uses$planting_method <- "drill_spring"  # not in this evaluation's planting_method_sets
  readr::write_csv(bad_uses, stbam_use_patterns_path(path))

  expect_error(build_baseline_from_evaluation(path),
              "absent from the selected planting-method set")
})

test_that("the adapter fails clearly when use_patterns.csv's planting methods disagree with the seeding set's own availability booleans", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- stbam_write_minimal_evaluation(evaluations_root, "Eval_Mismatch")

  # Add a second, otherwise-valid planting method to this evaluation's
  # planting_method_sets, then reference it in use_patterns.csv for Barley
  # -- but Barley's own seeding-set booleans only mark broadcast available
  # (drill_seeded = FALSE), so this must be rejected as a silently-dropped
  # (or silently-added) planting-method restriction, not accepted.
  planting <- read_named_set(path, "planting_method_sets", "default")
  planting <- dplyr::bind_rows(planting, tibble::tibble(
    planting_method_label = "Spring drill", planting_method = "drill_spring",
    surface_seed_fraction = 0.05, source = "hand", status = "ASSESSMENT_DEFAULT"
  ))
  write_named_set(path, "planting_method_sets", "default", planting,
                  tibble::tibble(set_id = "default", set_name = "default",
                                description = "", source = "", date_or_version = "",
                                status = "active", notes = ""))

  bad_uses <- read_use_patterns(path)
  bad_uses$planting_method <- "drill_spring"
  readr::write_csv(bad_uses, stbam_use_patterns_path(path))

  expect_error(build_baseline_from_evaluation(path),
              "do not exactly match the selected seeding set")
})

test_that("the adapter rejects a use_id whose OWN planting methods are narrower than the crop's availability, even when the crop-level aggregate across other rate levels would still match (independent-review finding: per-use, not per-crop, granularity)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- create_evaluation(evaluations_root, "Eval_PerUseNarrow")

  # A crop with two available planting methods.
  seeding <- read_named_set(path, "seeding_sets", "default")
  two_method_crop <- tibble::tibble(
    crop = "TestCrop", tkw_low_g_per_1000 = 40, tkw_high_g_per_1000 = 40,
    seeding_rate_low_seeds_per_ha_direct = NA_real_,
    seeding_rate_high_seeds_per_ha_direct = NA_real_,
    seeding_rate_low_kg_per_ha_low_tkw = 100, seeding_rate_low_kg_per_ha_high_tkw = 100,
    seeding_rate_high_kg_per_ha_low_tkw = 100, seeding_rate_high_kg_per_ha_high_tkw = 100,
    seeds_per_ha_low = 2500000, seeds_per_ha_high = 2500000,
    seeds_per_ha_low_basis = "CONVERTED_FROM_MASS",
    seeds_per_ha_high_basis = "CONVERTED_FROM_MASS",
    spring_seeded = TRUE, fall_seeded = FALSE, broadcast_seeded = TRUE,
    drill_seeded = TRUE, precision_planted = FALSE,
    source = "hand", status = "ASSESSMENT_DEFAULT"
  )
  write_named_set(path, "seeding_sets", "default",
                  dplyr::bind_rows(seeding, two_method_crop),
                  tibble::tibble(set_id = "default", set_name = "default",
                                description = "", source = "", date_or_version = "",
                                status = "active", notes = ""))

  # This evaluation's `create_evaluation()` default planting_method_sets
  # already came from the real data/reference/planting_method_parameters.csv
  # (via the fixture), which already includes `drill_spring` -- no need to
  # add it.

  # Two rate levels for TestCrop: "high" covers both methods (so the
  # crop-level aggregate matches the crop's full availability), but "low"
  # declares only broadcast -- a genuine per-use restriction the unchanged
  # engine cannot represent, since it re-derives the same crop-level method
  # set for every rate_level. This must be rejected, not silently widened.
  uses <- tibble::tribble(
    ~use_id, ~crop, ~rate_value, ~rate_unit, ~rate_level, ~planting_method, ~workbook,
    "u_high", "TestCrop", 300, "mg a.i./kg seed", "high", "broadcast", "wb",
    "u_high", "TestCrop", 300, "mg a.i./kg seed", "high", "drill_spring", "wb",
    "u_low",  "TestCrop", 100, "mg a.i./kg seed", "low",  "broadcast", "wb"
  )
  uses$product_identifier <- NA_character_
  uses$region <- NA_character_
  uses$target_pest <- NA_character_
  uses$notes <- NA_character_
  write_use_patterns(path, uses)

  expect_error(build_baseline_from_evaluation(path),
              "do not exactly match the selected seeding set")
})

test_that("the adapter rejects two distinct use_ids that collapse onto the same scenario identity (independent-review finding: silent duplicate-use collapse)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- stbam_write_minimal_evaluation(evaluations_root, "Eval_DupCollapse")

  uses <- read_use_patterns(path)
  duplicate_use <- uses
  duplicate_use$use_id <- "a_different_use_id_same_scenario"
  duplicate_use$product_identifier <- "A different product"
  combined <- dplyr::bind_rows(uses, duplicate_use)
  # Bypass write_use_patterns()'s own checks by writing directly -- this
  # simulates a hand-edited or externally-produced file, the same class of
  # input the adapter (not the GUI save path) must defend against.
  readr::write_csv(combined, stbam_use_patterns_path(path))

  expect_error(build_baseline_from_evaluation(path),
              "claimed by more than one use_id")
})

test_that("the adapter accepts a legitimately mistyped-looking but VALID set_ids category and rejects a genuinely unrecognized one (independent-review finding: silent set_ids typo)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- stbam_write_minimal_evaluation(evaluations_root, "Eval_SetIdsTypo")

  expect_error(
    build_baseline_from_evaluation(path, set_ids = list(seeding_set = "default")),
    "Unrecognized `set_ids` categor"
  )
  # The correctly-spelled category name still works.
  expect_no_error(
    build_baseline_from_evaluation(path, set_ids = list(seeding_sets = "default"))
  )
})

test_that("scenario_definitions' source/status/seed_use_number are preserved in migrated use_patterns.csv, not silently dropped (independent-review finding)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- migrate_to_evaluation(evaluations_root, "Eval_Provenance")

  use_patterns <- read_use_patterns(path)
  scenarios <- readr::read_csv(
    file.path(fixture, "data", "reference", "scenario_definitions.csv"),
    show_col_types = FALSE
  )
  # Every distinct `source` citation in the original scenario definitions
  # must survive somewhere in the migrated product_identifier column.
  expect_true(all(unique(scenarios$source) %in% unique(use_patterns$product_identifier)))
  # status/seed_use_number are preserved in notes, not silently dropped.
  expect_true(any(grepl("status=", use_patterns$notes, fixed = TRUE)))
  expect_true(any(grepl("seed_use_number=", use_patterns$notes, fixed = TRUE)))
})

test_that("the adapter never populates or depends on the legacy override layer", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- migrate_to_evaluation(evaluations_root, "Eval_NoOverrides")

  ps <- build_parameter_set_from_evaluation(path)
  expect_false(has_overrides(ps))
  expect_equal(nrow(ps$overrides), 0L)
})

test_that("the adapter supports selecting a non-default set_id per category", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  path <- stbam_write_minimal_evaluation(evaluations_root, "Eval_AltSet")

  alt_seeding <- read_named_set(path, "seeding_sets", "default")
  alt_seeding$tkw_low_g_per_1000 <- 999
  write_named_set(path, "seeding_sets", "alternative", alt_seeding,
                  tibble::tibble(set_id = "alternative", set_name = "alternative",
                                description = "", source = "", date_or_version = "",
                                status = "active", notes = ""))

  baseline_default <- build_baseline_from_evaluation(path)
  baseline_alt <- build_baseline_from_evaluation(
    path, set_ids = list(seeding_sets = "alternative")
  )
  expect_equal(baseline_default$crops$tkw_low_g_per_1000, 40)
  expect_equal(baseline_alt$crops$tkw_low_g_per_1000, 999)
})
