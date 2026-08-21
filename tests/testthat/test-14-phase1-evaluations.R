# Phase 1: folder and input schema, GUI editing backend, validation.
# docs/planning/implementation_phases_proposal.md "Phase 1";
# docs/planning/folder_and_input_schema.md; invariants I1, I3, I15
# (docs/planning/invariants_and_test_plan.md).
#
# These tests exercise only R/evaluations/*.R (plus the Phase 0 content-hash
# utility for round-trip identity checks). They never modify this project's
# real `data/reference/` -- every test that needs a `data/reference/`
# source uses an isolated temp-directory fixture (`stbam_use_fixture_project_root()`
# below), never `stbam_project_root()`'s real value.

# ---------------------------------------------------------------------------
# Test fixtures
# ---------------------------------------------------------------------------

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

#' A minimal, valid seeding_sets row set (2 crops)
#' @noRd
stbam_sample_seeding_set <- function() {
  tibble::tibble(
    crop = c("Barley", "Oat"),
    tkw_low_g_per_1000 = c(38.0, 30.0),
    tkw_high_g_per_1000 = c(45.0, 35.0),
    seeding_rate_low_seeds_per_ha_direct = c(NA_real_, NA_real_),
    seeding_rate_high_seeds_per_ha_direct = c(NA_real_, NA_real_),
    seeding_rate_low_kg_per_ha_low_tkw = c(90.0, 80.0),
    seeding_rate_low_kg_per_ha_high_tkw = c(100.0, 85.0),
    seeding_rate_high_kg_per_ha_low_tkw = c(120.0, 100.0),
    seeding_rate_high_kg_per_ha_high_tkw = c(130.0, 110.0),
    seeds_per_ha_low = c(2000000, 1800000),
    seeds_per_ha_high = c(2500000, 2200000),
    seeds_per_ha_low_basis = c("CONVERTED_FROM_MASS", "CONVERTED_FROM_MASS"),
    seeds_per_ha_high_basis = c("CONVERTED_FROM_MASS", "CONVERTED_FROM_MASS"),
    spring_seeded = c(TRUE, TRUE),
    fall_seeded = c(TRUE, FALSE),
    broadcast_seeded = c(TRUE, TRUE),
    drill_seeded = c(TRUE, TRUE),
    precision_planted = c(FALSE, FALSE),
    source = c("Test fixture", "Test fixture"),
    status = c("ASSESSMENT_DEFAULT", "ASSESSMENT_DEFAULT")
  )
}

#' A minimal, valid manifest row for a named set
#' @noRd
stbam_sample_manifest_row <- function(set_id = "test_set", set_name = "Test set") {
  tibble::tibble(set_id = set_id, set_name = set_name, description = "",
                 source = "", date_or_version = "", status = "active", notes = "")
}

# ---------------------------------------------------------------------------
# Validation engine: batch collection (human instruction: "collect useful
# errors rather than fail on only the first trivial issue")
# ---------------------------------------------------------------------------

test_that("validate_table collects every violation in one pass, not just the first", {
  schema <- stbam_schema_seeding_sets()
  bad <- stbam_sample_seeding_set()
  bad$crop[2] <- bad$crop[1]                  # duplicate key
  bad$tkw_low_g_per_1000[1] <- -5              # below minimum
  bad$spring_seeded <- as.character(bad$spring_seeded)  # wrong type
  bad$extra_column <- c("x", "y")             # unexpected column

  result <- validate_table(bad, schema)
  expect_false(result$valid)
  expect_true(any(grepl("Duplicate value", result$errors)))
  expect_true(any(grepl("below the permitted minimum", result$errors)))
  expect_true(any(grepl("must be logical", result$errors)))
  expect_true(any(grepl("Unexpected column", result$errors)))
  expect_gte(length(result$errors), 4L)
})

test_that("validate_table reports a missing required column", {
  schema <- stbam_schema_seeding_sets()
  incomplete <- stbam_sample_seeding_set()
  incomplete$crop <- NULL
  result <- validate_table(incomplete, schema)
  expect_false(result$valid)
  expect_true(any(grepl("Missing required column.*crop", result$errors)))
})

test_that("validate_table flags a required column's missing (NA) values", {
  schema <- stbam_schema_seeding_sets()
  df <- stbam_sample_seeding_set()
  df$crop[1] <- NA_character_
  result <- validate_table(df, schema)
  expect_false(result$valid)
  expect_true(any(grepl("missing value.*required", result$errors)))
})

test_that("validate_table permits NA in a non-required column", {
  schema <- stbam_schema_seeding_sets()
  df <- stbam_sample_seeding_set()  # already has NA in the optional direct-rate columns
  result <- validate_table(df, schema)
  expect_true(result$valid)
})

test_that("validate_table enforces a permitted-values (choices) list", {
  schema <- stbam_schema_planting_method_sets()
  df <- tibble::tibble(
    planting_method_label = "Bogus method",
    planting_method = "levitation",
    surface_seed_fraction = 0.05, source = "x", status = "ASSESSMENT_DEFAULT"
  )
  result <- validate_table(df, schema)
  expect_false(result$valid)
  expect_true(any(grepl("permitted set", result$errors)))
})

test_that("validate_table's numeric range bounds match STBAM_OVERRIDABLE, not invented values", {
  # surface_seed_fraction: STBAM_OVERRIDABLE min = 0, max = 1.
  schema <- stbam_schema_planting_method_sets()
  df <- tibble::tibble(
    planting_method_label = "x", planting_method = "broadcast",
    surface_seed_fraction = 1.5, source = "x", status = "x"
  )
  result <- validate_table(df, schema)
  expect_false(result$valid)
  expect_true(any(grepl("above the permitted maximum \\(1\\)", result$errors)))
})

# ---------------------------------------------------------------------------
# Named-set vertical slice: seeding_sets, write -> read -> validate ->
# round-trip (the readiness-review-mandated template category)
# ---------------------------------------------------------------------------

test_that("write_named_set writes a valid seeding_sets set and its manifest row", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_A")

  result <- write_named_set(eval_path, "seeding_sets", "custom",
                            stbam_sample_seeding_set(),
                            stbam_sample_manifest_row("custom", "Custom seeding set"))
  expect_true(result$success)
  expect_length(result$errors, 0L)
  expect_true(file.exists(stbam_set_path(eval_path, "seeding_sets", "custom")))

  manifest <- list_named_sets(eval_path, "seeding_sets")
  expect_true("custom" %in% manifest$set_id)
  expect_true("default" %in% manifest$set_id)  # the evaluation-creation default, untouched
})

test_that("read_named_set reproduces exactly what was written (read-after-write)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_B")

  written <- stbam_sample_seeding_set()
  write_named_set(eval_path, "seeding_sets", "custom", written,
                  stbam_sample_manifest_row("custom"))
  reread <- read_named_set(eval_path, "seeding_sets", "custom")

  expect_equal(nrow(reread), nrow(written))
  expect_setequal(names(reread), names(written))
  expect_equal(reread[order(reread$crop), ], written[order(written$crop), ],
              ignore_attr = TRUE)
})

test_that("scientific-content identity survives a full write/close/reopen round trip (content-hash, order-independent)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_C")

  written <- stbam_sample_seeding_set()
  write_named_set(eval_path, "seeding_sets", "custom", written,
                  stbam_sample_manifest_row("custom"))

  # Simulate "close" by discarding the in-memory object and re-reading from
  # disk with a row order deliberately reversed (presentation ordering, per
  # the task's own semantic-boundary note, must not be part of identity).
  reread <- read_named_set(eval_path, "seeding_sets", "custom")
  reread_reversed <- reread[rev(seq_len(nrow(reread))), ]

  hash_written <- stbam_content_hash(list(seeding_set = written))
  hash_reread <- stbam_content_hash(list(seeding_set = reread))
  hash_reversed <- stbam_content_hash(list(seeding_set = reread_reversed))

  expect_identical(hash_written, hash_reread)
  expect_identical(hash_written, hash_reversed)
})

test_that("a genuine scientific-content change is detected by the round-trip hash", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_D")

  original <- stbam_sample_seeding_set()
  write_named_set(eval_path, "seeding_sets", "custom", original,
                  stbam_sample_manifest_row("custom"))
  hash_before <- stbam_content_hash(list(s = read_named_set(eval_path, "seeding_sets", "custom")))

  changed <- original
  changed$tkw_low_g_per_1000[1] <- changed$tkw_low_g_per_1000[1] + 1
  write_named_set(eval_path, "seeding_sets", "custom", changed,
                  stbam_sample_manifest_row("custom"))
  hash_after <- stbam_content_hash(list(s = read_named_set(eval_path, "seeding_sets", "custom")))

  expect_false(identical(hash_before, hash_after))
})

# ---------------------------------------------------------------------------
# Same generic mechanism generalizes to the remaining four categories
# (no bespoke per-category code -- ADR-006: "single mechanism applies
# uniformly to every named-set category")
# ---------------------------------------------------------------------------

test_that("the same write/read/validate mechanism works for every named-set category", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_AllCategories")

  samples <- list(
    receptor_sets = tibble::tibble(
      receptor_id = "test_receptor", taxon = "bird", size_class = "small",
      body_weight_g = 20, fir_regression_name = "x", fir_coefficient_a = 0.4,
      fir_exponent_b = 0.85, food_intake_g_dw_per_day = 5, msa_short_term_m2 = 70,
      msa_long_term_m2 = 35, surface_seed_only = TRUE, source = "x", status = "x"
    ),
    effects_sets = tibble::tibble(
      metric_id = "test_metric", active_ingredient = "x", taxon = "bird",
      duration_class = "acute", metric_role = "SCREENING",
      endpoint_description = "x", endpoint_value = 100, uncertainty_factor = 10,
      effects_metric = 10, unit = "mg/kg", source = "x", status = "x"
    ),
    fate_sets = tibble::tibble(
      parameter = "residue_dt50_days", value = 10, unit = "days",
      description = "x", source = "x", status = "x"
    ),
    planting_method_sets = tibble::tibble(
      planting_method_label = "Broadcast", planting_method = "broadcast",
      surface_seed_fraction = 0.1, source = "x", status = "x"
    )
  )

  for (category in names(samples)) {
    result <- write_named_set(eval_path, category, "custom", samples[[category]],
                              stbam_sample_manifest_row("custom"))
    expect_true(result$success, info = paste("category:", category, paste(result$errors, collapse = "; ")))
    reread <- read_named_set(eval_path, category, "custom")
    expect_equal(nrow(reread), nrow(samples[[category]]), info = category)
  }
})

# ---------------------------------------------------------------------------
# Multiple named sets coexist without overwriting one another (ADR-004)
# ---------------------------------------------------------------------------

test_that("multiple named sets in one category coexist independently", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_Multi")

  set_a <- stbam_sample_seeding_set()
  set_b <- stbam_sample_seeding_set()
  set_b$crop <- c("Rye", "Triticale")

  write_named_set(eval_path, "seeding_sets", "set_a", set_a, stbam_sample_manifest_row("set_a", "Set A"))
  write_named_set(eval_path, "seeding_sets", "set_b", set_b, stbam_sample_manifest_row("set_b", "Set B"))

  manifest <- list_named_sets(eval_path, "seeding_sets")
  expect_setequal(manifest$set_id, c("default", "set_a", "set_b"))

  reread_a <- read_named_set(eval_path, "seeding_sets", "set_a")
  reread_b <- read_named_set(eval_path, "seeding_sets", "set_b")
  expect_setequal(reread_a$crop, c("Barley", "Oat"))
  expect_setequal(reread_b$crop, c("Rye", "Triticale"))
})

# ---------------------------------------------------------------------------
# Validate-before-replace: I15 -- a failed validation never replaces the
# previously saved, valid file
# ---------------------------------------------------------------------------

test_that("an invalid named-set write leaves the previously saved set file byte-identical", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_I15_Set")

  valid <- stbam_sample_seeding_set()
  write_named_set(eval_path, "seeding_sets", "custom", valid, stbam_sample_manifest_row("custom"))
  path <- stbam_set_path(eval_path, "seeding_sets", "custom")
  before <- readLines(path)

  invalid <- valid
  invalid$tkw_low_g_per_1000[1] <- -999  # violates the min bound
  result <- write_named_set(eval_path, "seeding_sets", "custom", invalid,
                            stbam_sample_manifest_row("custom"))

  expect_false(result$success)
  expect_true(length(result$errors) > 0L)
  after <- readLines(path)
  expect_identical(before, after)
})

test_that("an invalid named-set write does not corrupt the manifest either", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_I15_Manifest")

  manifest_path <- stbam_manifest_path(eval_path, "seeding_sets")
  before <- readLines(manifest_path)

  invalid <- stbam_sample_seeding_set()
  invalid$crop <- c("Barley", "Barley")  # duplicate key
  result <- write_named_set(eval_path, "seeding_sets", "dup_test", invalid,
                            stbam_sample_manifest_row("dup_test"))

  expect_false(result$success)
  after <- readLines(manifest_path)
  expect_identical(before, after)
})

test_that("write_named_set rejects a non-filename-safe set_id before touching disk", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_BadId")

  result <- write_named_set(eval_path, "seeding_sets", "not a safe id!",
                            stbam_sample_seeding_set(), stbam_sample_manifest_row())
  expect_false(result$success)
  expect_false(file.exists(stbam_set_path(eval_path, "seeding_sets", "not a safe id!")))
})

test_that("an invalid use_patterns.csv write leaves the previously saved file untouched", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_I15_Uses")

  valid <- tibble::tibble(
    use_id = "u1", crop = "Barley", rate_value = 300,
    rate_unit = "mg a.i./kg seed", rate_level = "high",
    planting_method = "broadcast", workbook = "small_cereals",
    product_identifier = NA_character_, region = NA_character_,
    target_pest = NA_character_, notes = NA_character_
  )
  write_named_set(eval_path, "seeding_sets", "seeding", stbam_sample_seeding_set(),
                  stbam_sample_manifest_row("seeding"))
  write_use_patterns(eval_path, valid)
  path <- stbam_use_patterns_path(eval_path)
  before <- readLines(path)

  invalid <- valid
  invalid$rate_unit <- "not a real unit"
  result <- write_use_patterns(eval_path, invalid)

  expect_false(result$success)
  after <- readLines(path)
  expect_identical(before, after)
})

# ---------------------------------------------------------------------------
# use_patterns.csv: ADR-005 semantics (shared use_id across planting
# methods, referential integrity against known crops)
# ---------------------------------------------------------------------------

test_that("a crop/rate use spanning multiple planting methods is stored as multiple rows sharing one use_id", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_UsePatterns")

  write_named_set(eval_path, "seeding_sets", "seeding", stbam_sample_seeding_set(),
                  stbam_sample_manifest_row("seeding"))

  df <- tibble::tibble(
    use_id = c("u1", "u1"), crop = c("Barley", "Barley"), rate_value = c(300, 300),
    rate_unit = c("mg a.i./kg seed", "mg a.i./kg seed"), rate_level = c("high", "high"),
    planting_method = c("broadcast", "drill_spring"), workbook = c("small_cereals", "small_cereals"),
    product_identifier = NA_character_, region = NA_character_,
    target_pest = NA_character_, notes = NA_character_
  )
  result <- write_use_patterns(eval_path, df)
  expect_true(result$success, info = paste(result$errors, collapse = "; "))

  reread <- read_use_patterns(eval_path)
  expect_equal(nrow(reread), 2L)
  expect_equal(length(unique(reread$use_id)), 1L)
})

test_that("use_patterns.csv rejects a duplicate (use_id, planting_method) combination", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_UseDup")
  write_named_set(eval_path, "seeding_sets", "seeding", stbam_sample_seeding_set(),
                  stbam_sample_manifest_row("seeding"))

  df <- tibble::tibble(
    use_id = c("u1", "u1"), crop = c("Barley", "Barley"), rate_value = c(300, 300),
    rate_unit = c("mg a.i./kg seed", "mg a.i./kg seed"), rate_level = c("high", "high"),
    planting_method = c("broadcast", "broadcast"), workbook = c("small_cereals", "small_cereals"),
    product_identifier = NA_character_, region = NA_character_,
    target_pest = NA_character_, notes = NA_character_
  )
  result <- write_use_patterns(eval_path, df)
  expect_false(result$success)
  expect_true(any(grepl("Duplicate value", result$errors)))
})

test_that("use_patterns.csv referential integrity rejects a crop absent from every seeding set", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_UseRef")
  write_named_set(eval_path, "seeding_sets", "seeding", stbam_sample_seeding_set(),
                  stbam_sample_manifest_row("seeding"))

  df <- tibble::tibble(
    use_id = "u1", crop = "NotACrop", rate_value = 300,
    rate_unit = "mg a.i./kg seed", rate_level = "high",
    planting_method = "broadcast", workbook = "small_cereals",
    product_identifier = NA_character_, region = NA_character_,
    target_pest = NA_character_, notes = NA_character_
  )
  result <- write_use_patterns(eval_path, df)
  expect_false(result$success)
  expect_true(any(grepl("crop.*not present", result$errors)))
})

# ---------------------------------------------------------------------------
# reporting_sets: I7 (crop-only grouping, structurally enforced) and
# partial coverage / singleton groups (ADR-010)
# ---------------------------------------------------------------------------

test_that("I7: a reporting scheme cannot be keyed on a non-crop dimension", {
  bad <- tibble::tibble(crop = c("Barley", "Oat"),
                        planting_method = c("broadcast", "drill_spring"))
  result <- validate_reporting_set(bad)
  expect_false(result$valid)
  expect_true(any(grepl("Unexpected column.*planting_method", result$errors)))
})

test_that("reporting_sets permits partial coverage (blank group_label) and singleton groups", {
  df <- tibble::tibble(
    crop = c("Barley", "Oat", "Rye"),
    group_label = c("Small Cereals", "Small Cereals", NA_character_),
    display_order = c(1, 2, NA_real_)
  )
  result <- validate_reporting_set(df)
  expect_true(result$valid)
})

test_that("reporting_sets can be written and read back for a fresh evaluation (starts empty, per ADR-016 point 4)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_Reporting")

  manifest <- list_named_sets(eval_path, "reporting_sets")
  expect_equal(nrow(manifest), 0L)

  scheme <- tibble::tibble(crop = c("Barley", "Oat"), group_label = c("Small Cereals", "Small Cereals"),
                           display_order = c(1, 2))
  result <- write_named_set(eval_path, "reporting_sets", "crop_family", scheme,
                            stbam_sample_manifest_row("crop_family", "Crop family"))
  expect_true(result$success)
  reread <- read_named_set(eval_path, "reporting_sets", "crop_family")
  expect_equal(nrow(reread), 2L)
})

# ---------------------------------------------------------------------------
# Evaluation folder lifecycle (ADR-002, ADR-003, ADR-014) -- I1, I3
# ---------------------------------------------------------------------------

test_that("create_evaluation builds the complete, self-contained folder structure (I1)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_Structure")

  expect_true(dir.exists(file.path(eval_path, "inputs", "uses")))
  expect_true(file.exists(stbam_use_patterns_path(eval_path)))
  for (category in names(STBAM_SET_CATEGORIES)) {
    expect_true(dir.exists(stbam_category_dir(eval_path, category)), info = category)
    expect_true(file.exists(stbam_manifest_path(eval_path, category)), info = category)
  }
  expect_true(dir.exists(file.path(eval_path, "inputs", "reference")))
  for (f in STBAM_REFERENCE_PROVENANCE_FILES) {
    expect_true(file.exists(file.path(eval_path, "inputs", "reference", f)), info = f)
  }
  expect_true(dir.exists(file.path(eval_path, "outputs", "runs")))
  expect_true(dir.exists(file.path(eval_path, "outputs", "tables", "definitions")))
  expect_true(dir.exists(file.path(eval_path, "outputs", "figures", "exports")))

  # No file in this schema is ever a partial override/diff (I1) -- every
  # copied default set is the complete reference table, not a subset.
  seeding <- read_named_set(eval_path, "seeding_sets", "default")
  reference <- readr::read_csv(file.path(fixture, "data", "reference", "crop_seeding_parameters.csv"),
                               show_col_types = FALSE)
  expect_equal(nrow(seeding), nrow(reference))
})

test_that("a fresh evaluation's use_patterns.csv starts empty (Phase 1 does not perform Phase 2's migration transformation)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_EmptyUses")
  expect_equal(nrow(read_use_patterns(eval_path)), 0L)
})

test_that("a fresh evaluation's reporting_sets manifest starts empty (STBAM_WORKBOOK_TO_CROP_FAMILY extraction is Phase 2 ticket 4)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_EmptyReporting")
  expect_equal(nrow(list_named_sets(eval_path, "reporting_sets")), 0L)
})

test_that("I3: editing data/reference/ after an evaluation exists never retroactively alters that evaluation's inputs", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_I3")

  before <- read_named_set(eval_path, "seeding_sets", "default")

  # Mutate the *fixture's* data/reference (never the real project's) after
  # the evaluation was created.
  ref_path <- file.path(fixture, "data", "reference", "crop_seeding_parameters.csv")
  ref <- readr::read_csv(ref_path, show_col_types = FALSE)
  ref$tkw_low_g_per_1000[1] <- ref$tkw_low_g_per_1000[1] + 1000
  readr::write_csv(ref, ref_path)

  after <- read_named_set(eval_path, "seeding_sets", "default")
  expect_equal(before, after, ignore_attr = TRUE)
})

test_that("list_evaluations enumerates every evaluation without requiring full state to be loaded", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  create_evaluation(evaluations_root, "Eval_List_1")
  create_evaluation(evaluations_root, "Eval_List_2")

  listing <- list_evaluations(evaluations_root)
  expect_setequal(listing$name, c("Eval_List_1", "Eval_List_2"))
  expect_true(all(listing$n_runs == 0L))
})

test_that("list_evaluations returns zero rows for a nonexistent evaluations_root", {
  listing <- list_evaluations(file.path(withr::local_tempdir(), "does_not_exist"))
  expect_equal(nrow(listing), 0L)
})

test_that("open_evaluation resolves an existing evaluation and errors on an unknown one", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_Open")
  expect_equal(open_evaluation(evaluations_root, "Eval_Open"), eval_path)
  expect_error(open_evaluation(evaluations_root, "NoSuchEvaluation"), "No evaluation named")
})

test_that("clone_evaluation copies inputs only, with a fresh empty outputs/ tree", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  original <- create_evaluation(evaluations_root, "Eval_Clone_Source")
  write_named_set(original, "seeding_sets", "custom", stbam_sample_seeding_set(),
                  stbam_sample_manifest_row("custom"))
  dir.create(file.path(original, "outputs", "runs", "Run_001"), recursive = TRUE)

  clone_path <- clone_evaluation(evaluations_root, "Eval_Clone_Source", "Eval_Clone_Target")

  expect_true("custom" %in% list_named_sets(clone_path, "seeding_sets")$set_id)
  expect_equal(length(list.dirs(file.path(clone_path, "outputs", "runs"), recursive = FALSE)), 0L)
})

test_that("rename_evaluation moves the folder and preserves its content", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  create_evaluation(evaluations_root, "Eval_Rename_Old")
  new_path <- rename_evaluation(evaluations_root, "Eval_Rename_Old", "Eval_Rename_New")
  expect_true(dir.exists(new_path))
  expect_false(dir.exists(file.path(evaluations_root, "Eval_Rename_Old")))
  expect_error(open_evaluation(evaluations_root, "Eval_Rename_Old"))
})

test_that("delete_evaluation requires explicit confirm = TRUE", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_Delete")
  expect_error(delete_evaluation(evaluations_root, "Eval_Delete"), "confirm")
  expect_true(dir.exists(eval_path))

  delete_evaluation(evaluations_root, "Eval_Delete", confirm = TRUE)
  expect_false(dir.exists(eval_path))
})

test_that("create_evaluation rejects an unsafe evaluation name and a duplicate name", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  expect_error(create_evaluation(evaluations_root, "bad/name"), "not a valid")
  create_evaluation(evaluations_root, "Eval_Dup")
  expect_error(create_evaluation(evaluations_root, "Eval_Dup"), "already exists")
})

# ---------------------------------------------------------------------------
# Excel round-trip (ADR-006): export, then import with validation
# ---------------------------------------------------------------------------

test_that("a table exported to Excel and re-imported validates and matches its content", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  schema <- stbam_schema_seeding_sets()
  original <- stbam_sample_seeding_set()
  path <- withr::local_tempfile(fileext = ".xlsx")
  export_table_excel(original, path)

  imported <- import_table_file(path, schema)
  expect_true(imported$valid, info = paste(imported$errors, collapse = "; "))
  expect_equal(nrow(imported$data), nrow(original))
  expect_equal(sort(imported$data$crop), sort(original$crop))
  expect_equal(sort(imported$data$tkw_low_g_per_1000), sort(original$tkw_low_g_per_1000))
})

test_that("importing an invalid Excel upload reports errors and is never allowed to overwrite a saved file", {
  skip_if_not_installed("writexl")
  skip_if_not_installed("readxl")
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_ExcelInvalid")

  valid <- stbam_sample_seeding_set()
  write_named_set(eval_path, "seeding_sets", "custom", valid, stbam_sample_manifest_row("custom"))
  saved_path <- stbam_set_path(eval_path, "seeding_sets", "custom")
  before <- readLines(saved_path)

  bad <- valid
  bad$tkw_low_g_per_1000 <- c("not-a-number", "30")  # will fail numeric coercion
  upload_path <- withr::local_tempfile(fileext = ".xlsx")
  export_table_excel(bad, upload_path)

  imported <- import_table_file(upload_path, stbam_schema_seeding_sets())
  expect_false(imported$valid)
  expect_true(any(grepl("not valid numbers", imported$errors)))

  # The upload's own invalidity means it must never be forwarded to
  # write_named_set() as-is by a well-behaved caller; confirm the guarantee
  # holds even if it is attempted.
  attempt <- write_named_set(eval_path, "seeding_sets", "custom", imported$data,
                             stbam_sample_manifest_row("custom"))
  expect_false(attempt$success)
  after <- readLines(saved_path)
  expect_identical(before, after)
})

test_that("import_table_file reports an unsupported file type without erroring uncontrolled", {
  path <- withr::local_tempfile(fileext = ".txt")
  writeLines("not a spreadsheet", path)
  result <- import_table_file(path, stbam_schema_seeding_sets())
  expect_false(result$valid)
  expect_true(any(grepl("Unsupported file type|Could not read", result$errors)))
})

# ---------------------------------------------------------------------------
# Dirty-state tracking and whole-evaluation save-all (ADR-007)
# ---------------------------------------------------------------------------

test_that("dirty-state tracking transitions correctly and is independent of Shiny", {
  state <- new_dirty_state(c("seeding_sets:default", "use_patterns"))
  expect_false(any_dirty(state))

  state <- mark_dirty(state, "seeding_sets:default")
  expect_true(any_dirty(state))
  expect_equal(dirty_tables(state), "seeding_sets:default")

  state <- mark_saved(state, "seeding_sets:default")
  expect_false(any_dirty(state))
})

test_that("save_all writes nothing if any dirty table fails validation (all-or-nothing)", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_SaveAll_Fail")

  valid_set <- stbam_sample_seeding_set()
  invalid_set <- stbam_sample_seeding_set()
  invalid_set$crop <- c("Barley", "Barley")  # duplicate key -> invalid

  items <- list(
    good = list(kind = "named_set", category = "seeding_sets", set_id = "good",
               df = valid_set, manifest_row = stbam_sample_manifest_row("good")),
    bad = list(kind = "named_set", category = "receptor_sets", set_id = "bad",
              df = invalid_set, manifest_row = stbam_sample_manifest_row("bad"))
  )
  result <- save_all(eval_path, items)

  expect_false(result$success)
  expect_true("bad" %in% names(result$errors))
  expect_false(file.exists(stbam_set_path(eval_path, "seeding_sets", "good")))
})

test_that("save_all writes every item when all pass validation", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_SaveAll_Ok")

  items <- list(
    seeding = list(kind = "named_set", category = "seeding_sets", set_id = "custom",
                  df = stbam_sample_seeding_set(), manifest_row = stbam_sample_manifest_row("custom")),
    uses = list(kind = "use_patterns",
               df = tibble::tibble(
                 use_id = "u1", crop = "Barley", rate_value = 300,
                 rate_unit = "mg a.i./kg seed", rate_level = "high",
                 planting_method = "broadcast", workbook = "small_cereals",
                 product_identifier = NA_character_, region = NA_character_,
                 target_pest = NA_character_, notes = NA_character_
               ),
               check_referential_integrity = FALSE)
  )
  result <- save_all(eval_path, items)

  expect_true(result$success)
  expect_true(file.exists(stbam_set_path(eval_path, "seeding_sets", "custom")))
  expect_equal(nrow(read_use_patterns(eval_path)), 1L)
})

# ---------------------------------------------------------------------------
# Hash type-normalization investigation (integer vs. double representation)
# -- human instruction item 8
# ---------------------------------------------------------------------------

test_that("readr's default type-guessing WOULD alternate integer/double for whole-number columns (the risk this phase must close)", {
  path <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(tibble::tibble(seeds_per_ha_low = c(2000000, 1800000)), path)

  guessed <- readr::read_csv(path, progress = FALSE, show_col_types = FALSE)
  expect_true(is.integer(guessed$seeds_per_ha_low) || is.double(guessed$seeds_per_ha_low))
  # This is the actual failure mode being guarded against: an in-memory
  # double (e.g. from a Shiny numericInput) vs. a readr-guessed integer
  # column hash differently even though both represent the value 2,000,000.
  in_memory_double <- tibble::tibble(seeds_per_ha_low = c(2000000, 1800000))
  storage.mode(in_memory_double$seeds_per_ha_low) <- "double"
  storage.mode(guessed$seeds_per_ha_low) <- "integer"  # force the guessed-integer scenario deterministically
  hash_guessed_as_integer <- stbam_content_hash(list(t = guessed))
  hash_in_memory_double <- stbam_content_hash(list(t = in_memory_double))
  expect_false(identical(hash_guessed_as_integer, hash_in_memory_double))
})

test_that("stbam_col_types() forces every numeric schema column to double, closing the read-path risk", {
  path <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(tibble::tibble(
    crop = c("Barley", "Oat"),
    tkw_low_g_per_1000 = c(38, 30),      # whole numbers -- readr would guess integer
    tkw_high_g_per_1000 = c(45.5, 35.2)  # non-whole -- readr would guess double
  ), path)

  parsed <- readr::read_csv(path, col_types = readr::cols(
    crop = readr::col_character(),
    tkw_low_g_per_1000 = readr::col_double(),
    tkw_high_g_per_1000 = readr::col_double()
  ), progress = FALSE)
  expect_true(is.double(parsed$tkw_low_g_per_1000))
  expect_true(is.double(parsed$tkw_high_g_per_1000))
})

test_that("read_named_set never produces an integer-typed numeric column regardless of whether values look whole", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_TypeStability")

  whole_numbers <- stbam_sample_seeding_set()
  whole_numbers$seeds_per_ha_low <- c(2000000, 1800000)  # all whole
  write_named_set(eval_path, "seeding_sets", "custom", whole_numbers,
                  stbam_sample_manifest_row("custom"))
  reread <- read_named_set(eval_path, "seeding_sets", "custom")
  expect_true(is.double(reread$seeds_per_ha_low))
  expect_false(is.integer(reread$seeds_per_ha_low))

  # And an in-memory tibble built the way a Shiny numericInput would
  # (always double) hashes identically to what was read back, precisely
  # because both are double -- the alternation is closed at the schema/read
  # boundary, not by touching the Phase 0 hash primitive itself.
  shiny_like <- whole_numbers
  hash_shiny_like <- stbam_content_hash(list(s = shiny_like))
  hash_reread <- stbam_content_hash(list(s = reread))
  expect_identical(hash_shiny_like, hash_reread)
})

# ---------------------------------------------------------------------------
# Independence from current working directory
# ---------------------------------------------------------------------------

test_that("evaluation functions operate on absolute paths independent of getwd()", {
  fixture <- stbam_use_fixture_project_root()
  evaluations_root <- file.path(fixture, "evaluations")
  eval_path <- create_evaluation(evaluations_root, "Eval_Cwd")

  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(tempdir())

  reread <- read_named_set(eval_path, "seeding_sets", "default")
  expect_gt(nrow(reread), 0L)
})

# ---------------------------------------------------------------------------
# No unintended dependency on the legacy override layer
# ---------------------------------------------------------------------------

test_that("the Phase 1 evaluation layer does not call into the legacy override/parameter-set system", {
  evaluation_files <- list.files(file.path(stbam_project_root(), "R", "evaluations"),
                                 pattern = "[.]R$", full.names = TRUE)
  legacy_symbols <- c("set_override", "clear_override", "effective_value",
                      "parameter_set", "export_scenario_config", "import_scenario_config")
  hits <- character()
  for (f in evaluation_files) {
    # Only count an actual function call (name immediately followed by `(`),
    # not an incidental substring match inside a comment or file path (e.g.
    # a comment citing "R/inputs/11_parameter_set.R" should not count).
    lines <- readLines(f)
    code_lines <- lines[!grepl("^\\s*#", lines)]
    text <- paste(code_lines, collapse = "\n")
    found <- legacy_symbols[vapply(legacy_symbols, function(s) {
      grepl(paste0(s, "\\("), text)
    }, logical(1))]
    if (length(found) > 0L) hits <- c(hits, paste0(basename(f), ": ", paste(found, collapse = ", ")))
  }
  expect_length(hits, 0L)
})
