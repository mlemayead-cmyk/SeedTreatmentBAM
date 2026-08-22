# Phase 2: one-time migration of the current project's data/reference/*.csv +
# scenario_definitions.csv into a complete evaluation (ADR-015).
#
# docs/planning/migration_plan.md. Reuses create_evaluation()
# (R/evaluations/54_evaluation_folder.R) unchanged for the generic
# wholesale-copy part -- this file only implements the two genuinely
# migration-specific transformations (scenario_definitions -> use_patterns,
# ADR-005; STBAM_WORKBOOK_TO_CROP_FAMILY extraction, ADR-010/ADR-016) plus
# tier-1/supporting provenance writes.
#
# Deliberately kept in a separate R/migration/ directory, not
# R/evaluations/: the Phase 1 evaluation-persistence layer is tested
# (test-14-phase1-evaluations.R, "does not call into the legacy
# override/parameter-set system") to have zero dependency on
# parameter_set()/the override system, which is correct for that layer but
# not for this one -- this file's whole job is a one-time data
# transformation, and 20_engine_adapter.R's job is specifically to hand off
# to parameter_set() for the unchanged engine (migration_plan.md §3 step 4).
# Keeping the two concerns in different directories keeps that Phase 1
# invariant honestly enforced rather than narrowing its own test.
#
# Does NOT fabricate a run (migration_plan.md §3 step 5) -- migration produces
# valid inputs/ only.

#' Transform `scenario_definitions.csv` into `use_patterns.csv` rows (ADR-005)
#'
#' One row per (workbook, crop, rate_level, rate_value, rate_unit)
#' combination x each planting method available for that crop, sharing one
#' `use_id` across the planting-method rows for the same combination
#' (ADR-005). The numeric rate and its unit are part of the `use_id`, not
#' just workbook/crop/rate_level -- several legume crops have both a
#' mg/kg-seed and a mg/seed use sharing the same `rate_level`
#' (`R/summaries/20_scenario_inputs.R`'s own `scenario_id` construction
#' notes the identical reason: omitting rate value/unit silently collides
#' two scientifically different uses under one identifier). Planting-method
#' availability is read via [available_planting_methods()] -- the same
#' function the unchanged engine itself calls -- so migration and the
#' engine can never silently disagree about which methods a crop permits.
#'
#' `scenario_definitions.csv`'s own `source` column (a registration/label
#' citation, e.g. `"VUI 3622323"` or `"CRUISER(R) 5FS Seed Treatment label,
#' Reg. No. 27045"`) maps directly to `use_patterns.csv`'s
#' `product_identifier` -- that is exactly the registration/context
#' metadata that column exists for (`folder_and_input_schema.md` §3), not a
#' new invented use. `status` and `seed_use_number` have no dedicated
#' column in the frozen Phase 1 `use_patterns.csv` schema, so they are
#' preserved in `notes` (free text) rather than silently dropped
#' (independent-review finding, ADR-019: per-scenario provenance/context
#' must not vanish with no field anywhere to recover it).
#'
#' @param scenarios `data/reference/scenario_definitions.csv`-shaped tibble
#'   (or equivalent: `workbook`, `crop`, `rate_level`, `application_rate`,
#'   `application_rate_unit`, and optionally `source`, `status`,
#'   `seed_use_number`).
#' @param crops `data/reference/crop_seeding_parameters.csv`-shaped tibble.
#' @return A tibble matching [stbam_schema_use_patterns()].
#' @export
stbam_transform_use_patterns <- function(scenarios, crops) {
  key <- paste(
    scenarios$workbook, scenarios$crop, scenarios$rate_level,
    format(scenarios$application_rate, scientific = FALSE, trim = TRUE,
           digits = 15),
    scenarios$application_rate_unit,
    sep = "|"
  )
  if (anyDuplicated(key) != 0L) {
    stbam_abort(
      "scenario_definitions has duplicate workbook/crop/rate_level/rate/unit ",
      "combinations; cannot assign a stable use_id: ",
      paste(unique(key[duplicated(key)]), collapse = ", ")
    )
  }

  rows <- vector("list", nrow(scenarios))
  for (i in seq_len(nrow(scenarios))) {
    scenario <- scenarios[i, ]
    crop_row <- crops[crops$crop == scenario$crop, ][1, ]
    if (nrow(crop_row) == 0L || is.na(crop_row$crop[[1]])) {
      stbam_abort(
        "Crop `", scenario$crop, "` is present in scenario_definitions but ",
        "absent from the seeding-set data; cannot migrate its use pattern."
      )
    }
    methods <- available_planting_methods(crop_row)
    if (length(methods) == 0L) {
      stbam_abort(
        "Crop `", scenario$crop, "` has no available planting method in the ",
        "seeding-set data; cannot migrate its use pattern."
      )
    }
    source_val <- if ("source" %in% names(scenario)) scenario$source[[1]] else NA_character_
    status_val <- if ("status" %in% names(scenario)) scenario$status[[1]] else NA_character_
    seed_use_val <- if ("seed_use_number" %in% names(scenario)) {
      scenario$seed_use_number[[1]]
    } else {
      NA_real_
    }
    note_parts <- character()
    if (!is.na(seed_use_val)) {
      note_parts <- c(note_parts, paste0("seed_use_number=", format(seed_use_val, trim = TRUE)))
    }
    if (!is.na(status_val)) {
      note_parts <- c(note_parts, paste0("status=", status_val))
    }
    notes_val <- if (length(note_parts) > 0L) paste(note_parts, collapse = "; ") else NA_character_

    rows[[i]] <- tibble::tibble(
      use_id = key[[i]],
      crop = scenario$crop,
      rate_value = as.double(scenario$application_rate),
      rate_unit = scenario$application_rate_unit,
      rate_level = scenario$rate_level,
      planting_method = methods,
      workbook = scenario$workbook,
      product_identifier = source_val,
      region = NA_character_,
      target_pest = NA_character_,
      notes = notes_val
    )
  }
  dplyr::bind_rows(rows)
}

#' Extract `STBAM_WORKBOOK_TO_CROP_FAMILY` into a reporting_sets scheme
#' (ADR-010, ADR-016)
#'
#' `reporting_sets` schemes are crop-only (I7) -- the workbook-keyed R
#' constant is expanded to one row per crop actually modelled, via the
#' workbook(s) that crop appears under.
#'
#' @param scenarios `data/reference/scenario_definitions.csv`-shaped tibble.
#' @return A tibble matching [stbam_schema_reporting_sets()].
#' @export
stbam_extract_crop_family_reporting_set <- function(scenarios) {
  crop_workbook <- unique(scenarios[, c("crop", "workbook")])
  crop_workbook$group_label <- unname(
    STBAM_WORKBOOK_TO_CROP_FAMILY[crop_workbook$workbook]
  )
  if (anyNA(crop_workbook$group_label)) {
    missing <- unique(crop_workbook$workbook[is.na(crop_workbook$group_label)])
    stbam_abort("STBAM_WORKBOOK_TO_CROP_FAMILY has no mapping for workbook(s): ",
                paste(missing, collapse = ", "))
  }

  out <- unique(crop_workbook[, c("crop", "group_label")])
  dup_crop <- out$crop[duplicated(out$crop)]
  if (length(dup_crop) > 0L) {
    stbam_abort(
      "Crop(s) map to more than one crop family across workbooks -- I7 ",
      "(a reporting scheme groups crops only, unambiguously) would be ",
      "violated: ", paste(unique(dup_crop), collapse = ", ")
    )
  }
  out <- out[order(out$crop), , drop = FALSE]
  out$display_order <- NA_real_
  tibble::as_tibble(out[, c("crop", "group_label", "display_order")])
}

#' The Table 162 source document's independently-verified SHA-256
#'
#' Not present in `data/reference/source_manifest.csv` (that file covers
#' only the 6 calculation workbooks). Verified against the sibling
#' project's own pinned baseline for this file (`migration_plan.md` §0.1)
#' and, independently, by direct SHA-256 recomputation against the file on
#' disk during this phase's implementation.
#' @noRd
STBAM_TABLE162_DOCUMENT_SHA256 <-
  "ea76adfa0044db808867d880325a1932b891a1d72566f4a8c7b8752a0a36fb6a"

#' Relative paths (from the sibling project's root) for tier-1 source
#' documents, as verified in `migration_plan.md` §0.1.
#' @noRd
STBAM_TIER1_RELATIVE_PATHS <- c(
  small_cereals = paste0("Documents/Calculation Workbooks/THE 1 small cereals ",
                         "Bird and Mammal Seed Treatment RA Workbook 2026 for ",
                         "QAQC 08MAY2026.xlsm"),
  small_cereals_msa = paste0("Documents/THE 1b small cereals Bird and Mammal ",
                             "Seed Treatment RA Workbook 2026 for QAQC ",
                             "08MAY2026 MSA doses.xlsm"),
  canola = paste0("Documents/THE 2 canola rapeseed mustard Bird and Mammal ",
                  "Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA ",
                  "doses.xlsm"),
  legumes_deep = paste0("Documents/Calculation Workbooks/THE 3 deep legumes ",
                        "Bird and Mammal Seed Treatment RA Workbook 2026 for ",
                        "QAQC 08MAY2026 MSA doses.xlsm"),
  legumes_shallow = paste0("Documents/Calculation Workbooks/THE 3 shallow ",
                          "legumes Bird and Mammal Seed Treatment RA Workbook ",
                          "2026 for QAQC 08MAY2026 MSA doses.xlsm"),
  cucurbits = paste0("Documents/Calculation Workbooks/THE 5 cucurbits Bird ",
                     "and Mammal Seed Treatment RA Workbook 2026 for QAQC ",
                     "08MAY2026 MSA doses.xlsm"),
  table162_document = paste0("THE BAM ST RA - interim draft TABLES and FIGS ",
                             "- LIVE.mdlAug26.docx")
)

#' Build the tier-1 provenance table written into a migrated evaluation
#' (ADR-018, migration_plan.md §2.1)
#'
#' Path + SHA-256 references only -- the referenced files are never read or
#' copied by this function. Workbook hashes come from this project's own
#' already-verified `source_manifest.csv` (re-confirmed live against the
#' sibling project's files during this phase's implementation, not
#' re-hashed here); the Table 162 document hash is the independently
#' verified constant above. The sibling project is not a runtime dependency
#' of this migration.
#'
#' @param source_manifest `data/reference/source_manifest.csv`-shaped tibble.
#' @return A tibble: `workbook_key`, `file_name`, `role`, `sha256`,
#'   `relative_path`, `sibling_project_root`, `copied_into_evaluation`,
#'   `provenance_note`.
#' @export
stbam_tier1_provenance_table <- function(source_manifest) {
  workbooks <- tibble::tibble(
    workbook_key = source_manifest$workbook_key,
    file_name = source_manifest$file_name,
    role = source_manifest$role,
    sha256 = source_manifest$sha256
  )
  doc <- tibble::tibble(
    workbook_key = "table162_document",
    file_name = basename(STBAM_TIER1_RELATIVE_PATHS[["table162_document"]]),
    role = "TABLE162_SOURCE_DOCUMENT",
    sha256 = STBAM_TABLE162_DOCUMENT_SHA256
  )
  out <- dplyr::bind_rows(workbooks, doc)
  out$relative_path <- unname(STBAM_TIER1_RELATIVE_PATHS[out$workbook_key])
  out$sibling_project_root <-
    "C:/MonDossierMartin/Python_Local/Python_Document analysis"
  out$copied_into_evaluation <- FALSE
  out$provenance_note <- paste(
    "Tier-1 original; referenced by path + SHA-256 only, never copied",
    "(ADR-018). Not read by this project at run time."
  )
  out
}

#' Migrate the current project into a new, complete evaluation
#'
#' One-time, re-runnable (migration_plan.md §4 point 9): re-running against
#' an unchanged `data/reference/` under a new `name` produces byte-identical
#' `inputs/`; re-running with the same `name` fails cleanly (via
#' [create_evaluation()]'s own "already exists" guard) rather than silently
#' overwriting -- no separate overwrite behaviour is invented here.
#'
#' @param evaluations_root The `evaluations/` directory (created if absent).
#' @param name The new evaluation's folder name.
#' @return The new evaluation's path, invisibly.
#' @export
migrate_to_evaluation <- function(evaluations_root, name) {
  baseline <- load_baseline()

  evaluation_path <- create_evaluation(evaluations_root, name)

  use_patterns <- stbam_transform_use_patterns(baseline$scenarios, baseline$crops)
  use_result <- write_use_patterns(evaluation_path, use_patterns,
                                   check_referential_integrity = TRUE)
  if (!use_result$success) {
    stbam_abort("Migration failed writing use_patterns.csv: ",
                paste(use_result$errors, collapse = " "))
  }

  crop_family <- stbam_extract_crop_family_reporting_set(baseline$scenarios)
  reporting_result <- write_named_set(
    evaluation_path, "reporting_sets", "crop_family", crop_family,
    tibble::tibble(
      set_id = "crop_family", set_name = "Crop family (workbook-derived)",
      description = paste(
        "Extracted from the hard-coded STBAM_WORKBOOK_TO_CROP_FAMILY R",
        "constant (R/summaries/24_table162_support.R) at migration time.",
        "Migration ticket 4, ADR-010/ADR-016."
      ),
      source = "STBAM_WORKBOOK_TO_CROP_FAMILY",
      date_or_version = as.character(Sys.Date()),
      status = "active", notes = ""
    )
  )
  if (!reporting_result$success) {
    stbam_abort("Migration failed writing reporting_sets/crop_family: ",
                paste(reporting_result$errors, collapse = " "))
  }

  reference_dir <- file.path(evaluation_path, "inputs", "reference")
  tier1 <- stbam_tier1_provenance_table(baseline$source_manifest)
  readr::write_csv(tier1, file.path(reference_dir, "tier1_source_provenance.csv"))

  # fir_regressions.csv: preserved supporting reference data (tier-2,
  # loaded into the current baseline but consumed by no calculation --
  # docs/current_implementation_inventory.md §15 R3). Not folded into any
  # named-set category (migration_plan.md §2.2 leaves its placement open
  # and no code joins it to anything); copied unchanged so it is not
  # silently lost.
  fir_src <- file.path(stbam_project_root(), "data", "reference",
                       "fir_regressions.csv")
  if (file.exists(fir_src)) {
    file.copy(fir_src, file.path(reference_dir, "fir_regressions.csv"),
              overwrite = TRUE)
  }

  invisible(evaluation_path)
}
