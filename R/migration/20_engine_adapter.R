# Phase 2: evaluation-inputs -> engine-parameter-set adapter.
#
# docs/planning/migration_plan.md §3 step 4. The key new integration boundary:
# reads a complete evaluation's selected named sets + use_patterns.csv and
# produces an `stbam_baseline`/`stbam_parameter_set` object the *unchanged*
# build_scenario_inputs()/build_scenario_summary() consume directly -- no
# change to those functions' signatures or behaviour (I16).
#
# Never invents a default missing from the evaluation, never falls back to
# data/reference/ (the legacy global baseline), never uses the override layer
# as a persistence mechanism, and never silently drops named-set identity or
# planting-method restrictions -- every failure mode below aborts loudly
# instead (ADR-019 category 2: mandatory independent review).

#' Read a copied provenance/reference file from an evaluation's
#' `inputs/reference/`
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param file_name File name under `inputs/reference/`.
#' @param required If `TRUE` (default), aborts if the file is missing. If
#'   `FALSE`, returns `NULL` (used for supporting data no calculation
#'   consumes, e.g. `fir_regressions.csv` -- see
#'   `docs/current_implementation_inventory.md` §15 R3).
#' @return A tibble, or `NULL`.
#' @noRd
stbam_read_evaluation_reference <- function(evaluation_path, file_name,
                                            required = TRUE) {
  path <- file.path(evaluation_path, "inputs", "reference", file_name)
  if (!file.exists(path)) {
    if (required) {
      stbam_abort("Required reference file not found in evaluation: ", path)
    }
    return(NULL)
  }
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

#' Build an `stbam_baseline`-shaped object from an evaluation's inputs
#'
#' The evaluation-inputs -> engine-parameter-set adapter. Reads exactly the
#' selected named sets (default `set_id = "default"` per category, i.e. the
#' migrated/assessment-default set) and `use_patterns.csv`; reconstructs the
#' `workbook x crop x rate_level` scenario table
#' [build_scenario_inputs()] expects (planting-method eligibility is
#' re-derived by the unchanged engine from the seeding set's own booleans,
#' exactly as today -- `use_patterns.csv`'s per-row planting method is
#' cross-checked against that same derivation below, not substituted for
#' it).
#'
#' Fails loudly, rather than silently substituting a legacy or default
#' value, when: `set_ids` names an unrecognized category (a mistyped key
#' would otherwise silently fall back to `"default"`); a required category
#' has no set with the requested `set_id` (missing input);
#' `use_patterns.csv` is absent or empty; `use_patterns.csv` references a
#' crop or planting method not present in the selected sets (unresolved
#' reference); a single `use_id`'s own planting methods disagree with what
#' the selected seeding set's own availability booleans say (a per-use
#' restriction narrower or wider than the crop level cannot be represented
#' by the unchanged engine); or two distinct `use_id`s collapse onto the
#' same scenario identity (workbook/crop/rate_level/rate/unit), which would
#' silently merge two declared uses into one scenario row.
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param set_ids Optional named list overriding which `set_id` to use per
#'   category (`seeding_sets`, `planting_method_sets`, `receptor_sets`,
#'   `effects_sets`, `fate_sets`); defaults to `"default"` for every
#'   category not named. Multi-set *selection-per-run* bookkeeping belongs
#'   to Phase 3's run lifecycle, not this adapter.
#' @return An `stbam_baseline` (class `c("stbam_baseline", "list")`), the
#'   same shape [load_baseline()] returns.
#' @export
build_baseline_from_evaluation <- function(evaluation_path, set_ids = list()) {
  if (!dir.exists(evaluation_path)) {
    stbam_abort("No evaluation found at ", evaluation_path, ".")
  }

  if (length(set_ids) > 0L) {
    unrecognized <- setdiff(names(set_ids), names(STBAM_SET_CATEGORIES))
    if (length(unrecognized) > 0L) {
      stbam_abort(
        "Unrecognized `set_ids` categor(y/ies): ",
        paste(unrecognized, collapse = ", "), ". Known categories: ",
        paste(names(STBAM_SET_CATEGORIES), collapse = ", "),
        ". (A mistyped key would otherwise be silently ignored and fall ",
        "back to \"default\", which is exactly the silent-substitution ",
        "this adapter must not do.)"
      )
    }
  }

  resolve_set_id <- function(category) {
    requested <- set_ids[[category]]
    if (!is.null(requested)) requested else "default"
  }

  read_one <- function(category) {
    set_id <- resolve_set_id(category)
    manifest <- list_named_sets(evaluation_path, category)
    if (!set_id %in% manifest$set_id) {
      stbam_abort(
        "Evaluation at ", evaluation_path, " has no `", category,
        "` set with set_id `", set_id, "`. Available: ",
        if (nrow(manifest) == 0L) "(none)" else paste(manifest$set_id, collapse = ", "),
        "."
      )
    }
    read_named_set(evaluation_path, category, set_id)
  }

  crops <- read_one("seeding_sets")
  planting_methods <- read_one("planting_method_sets")
  receptors <- read_one("receptor_sets")
  effects_metrics <- read_one("effects_sets")
  fate <- read_one("fate_sets")

  use_patterns <- read_use_patterns(evaluation_path)
  if (nrow(use_patterns) == 0L) {
    stbam_abort("Evaluation at ", evaluation_path,
                " has an empty use_patterns.csv; nothing to build.")
  }

  unknown_crops <- setdiff(unique(use_patterns$crop), crops$crop)
  if (length(unknown_crops) > 0L) {
    stbam_abort("use_patterns.csv references crop(s) absent from the ",
                "selected seeding set (`", resolve_set_id("seeding_sets"),
                "`): ", paste(unknown_crops, collapse = ", "))
  }
  unknown_methods <- setdiff(unique(use_patterns$planting_method),
                             planting_methods$planting_method)
  if (length(unknown_methods) > 0L) {
    stbam_abort("use_patterns.csv references planting method(s) absent from ",
                "the selected planting-method set (`",
                resolve_set_id("planting_method_sets"), "`): ",
                paste(unknown_methods, collapse = ", "))
  }

  # Scenario identity key -- must match exactly what build_scenario_inputs()
  # (via its own scenario_id) treats as one distinct scenario: workbook,
  # crop, rate_level, AND the numeric rate/unit (several legume crops share
  # a rate_level across two distinct mg/kg-seed vs. mg/seed uses --
  # R/summaries/20_scenario_inputs.R's own scenario_id construction notes
  # the identical reason).
  scenario_key <- paste(
    use_patterns$workbook, use_patterns$crop, use_patterns$rate_level,
    format(use_patterns$rate_value, scientific = FALSE, trim = TRUE, digits = 15),
    use_patterns$rate_unit, sep = "|"
  )

  # Per-use_id granularity guard (independent-review finding, ADR-019):
  # checking planting-method availability only at the crop level (as an
  # earlier version of this function did) would silently accept a
  # use_patterns.csv where one specific use (one scenario_key) declares a
  # NARROWER planting-method set than the crop's own availability booleans
  # -- build_scenario_inputs() re-derives the crop-level set uniformly for
  # every rate_level regardless, so a genuine per-use restriction narrower
  # than the crop level cannot be honoured by the unchanged engine. Rather
  # than silently let the wider crop-level default win (exactly the
  # silent-substitution this adapter must not do), check per use_id and
  # abort if any use's own method set does not exactly equal the crop's.
  for (use in unique(use_patterns$use_id)) {
    use_rows <- use_patterns[use_patterns$use_id == use, ]
    use_crops <- unique(use_rows$crop)
    if (length(use_crops) != 1L) {
      stbam_abort("use_id `", use, "` spans more than one crop (",
                  paste(use_crops, collapse = ", "),
                  "); a use_id must identify a single crop/rate use.")
    }
    crop_row <- crops[crops$crop == use_crops, ][1, ]
    expected_methods <- sort(available_planting_methods(crop_row))
    observed_methods <- sort(unique(use_rows$planting_method))
    if (!identical(expected_methods, observed_methods)) {
      stbam_abort(
        "use_id `", use, "` (crop `", use_crops, "`): its planting methods ",
        "in use_patterns.csv (", paste(observed_methods, collapse = ", "),
        ") do not exactly match the selected seeding set's available ",
        "methods (", paste(expected_methods, collapse = ", "), "). The ",
        "unchanged engine cannot represent a per-use planting-method ",
        "restriction narrower or wider than the crop's own availability; ",
        "this evaluation cannot be adapted without either correcting ",
        "use_patterns.csv or changing the seeding set's availability."
      )
    }
  }

  # Duplicate-use collapse guard (independent-review finding, ADR-019):
  # reconstructing the scenario table by de-duplicating on scenario_key
  # would silently merge two DIFFERENT use_ids (e.g. two distinct
  # registered products at the same crop/rate) into one scenario row,
  # losing their separate identity with no error. A scenario_key must map
  # to exactly one use_id; multiple planting-method rows sharing that
  # use_id are the expected, lossless case (ADR-005) and are what actually
  # collapses below.
  key_to_use <- unique(data.frame(scenario_key = scenario_key,
                                  use_id = use_patterns$use_id,
                                  stringsAsFactors = FALSE))
  dup_keys <- key_to_use$scenario_key[duplicated(key_to_use$scenario_key)]
  if (length(dup_keys) > 0L) {
    culprits <- key_to_use[key_to_use$scenario_key %in% dup_keys, ]
    stbam_abort(
      "use_patterns.csv has ", length(unique(dup_keys)), " scenario ",
      "identity/identities (workbook|crop|rate_level|rate_value|rate_unit) ",
      "claimed by more than one use_id -- this would silently collapse ",
      "distinct declared uses into one scenario row: ",
      paste(sprintf("%s (use_ids: %s)", unique(culprits$scenario_key),
                    sapply(unique(culprits$scenario_key), function(k) {
                      paste(culprits$use_id[culprits$scenario_key == k], collapse = ", ")
                    })), collapse = "; "),
      "."
    )
  }

  # Reconstruct the workbook x crop x rate_level scenario table -- lossless
  # because (per the two guards above) every scenario_key maps to exactly
  # one use_id, and that use_id's own planting-method set is confirmed
  # identical to what the crop-level booleans re-derive.
  scenarios <- unique(use_patterns[, c("workbook", "crop", "rate_level",
                                       "rate_value", "rate_unit")])
  names(scenarios)[names(scenarios) == "rate_value"] <- "application_rate"
  names(scenarios)[names(scenarios) == "rate_unit"] <- "application_rate_unit"
  scenarios <- tibble::as_tibble(scenarios)

  source_manifest <- stbam_read_evaluation_reference(evaluation_path,
                                                      "source_manifest.csv")
  fir_regressions <- stbam_read_evaluation_reference(
    evaluation_path, "fir_regressions.csv", required = FALSE
  )
  if (is.null(fir_regressions)) fir_regressions <- tibble::tibble()

  baseline <- list(
    crops = crops,
    planting_methods = planting_methods,
    receptors = receptors,
    fir_regressions = fir_regressions,
    effects_metrics = effects_metrics,
    dissipation = fate,
    scenarios = scenarios,
    source_manifest = source_manifest
  )
  structure(baseline, class = c("stbam_baseline", "list"))
}

#' Build an `stbam_parameter_set` directly from an evaluation's inputs
#'
#' Convenience wrapper: [build_baseline_from_evaluation()] followed by
#' [parameter_set()] with an empty override layer -- the adapter never
#' populates or depends on the override mechanism; it is used only as the
#' engine's own required wrapper type.
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param name A short label for the resulting parameter set.
#' @param set_ids Passed to [build_baseline_from_evaluation()].
#' @return An `stbam_parameter_set`.
#' @export
build_parameter_set_from_evaluation <- function(evaluation_path,
                                                name = basename(evaluation_path),
                                                set_ids = list()) {
  baseline <- build_baseline_from_evaluation(evaluation_path, set_ids = set_ids)
  parameter_set(baseline, name = name)
}
