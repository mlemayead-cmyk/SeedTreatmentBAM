# Phase 1: evaluation folder lifecycle (ADR-002, ADR-003, ADR-014).
#
# docs/planning/folder_and_input_schema.md §1, §1.1. An evaluation is the
# persistence unit: `evaluations/<Name>/{inputs/, outputs/}`. This file
# implements Create/Open/Clone/Rename/Delete (implementation_phases_proposal.md
# Phase 1 ticket 1) -- the picker screen (Shiny) is a thin view over these
# functions, not a second implementation of them.
#
# What "Create" does NOT do (deliberately, out of Phase 1 scope):
#   - transform data/reference/scenario_definitions.csv into use_patterns.csv
#     rows (ADR-005's normalization) -- that specific transformation is
#     Phase 2 migration ticket 1, not generic evaluation creation. A new
#     Phase 1 evaluation's use_patterns.csv starts empty.
#   - extract STBAM_WORKBOOK_TO_CROP_FAMILY into a reporting_sets/ scheme --
#     Phase 2 migration ticket 4 (ADR-016 point 4). A new Phase 1
#     evaluation's reporting_sets/ starts with an empty manifest.
# What it DOES do: copy data/reference/ wholesale as each category's
# starting "default" named set (ADR-003), and copy the tier-2/tier-3
# provenance-only reference files into inputs/reference/ (ADR-018) -- both
# are the *generic* evaluation-creation mechanism ADR-003/004/018 describe
# for any evaluation, not a one-time migration of this project's specific
# historical assessment.

#' Is `name` a safe, plain evaluation-folder name?
#' @noRd
stbam_is_evaluation_name_safe <- function(name) {
  is.character(name) && length(name) == 1L && !is.na(name) && nzchar(name) &&
    !grepl("[\\\\/:*?\"<>|]", name) && name != "." && name != ".."
}

#' The standard empty `outputs/` tree for a new evaluation (ADR-002, ADR-008)
#' @noRd
stbam_create_outputs_tree <- function(evaluation_path) {
  for (sub in c("outputs/runs", "outputs/tables/definitions", "outputs/tables/exports",
                "outputs/figures/definitions", "outputs/figures/exports")) {
    dir.create(file.path(evaluation_path, sub), recursive = TRUE, showWarnings = FALSE)
  }
  invisible(evaluation_path)
}

#' Read a `data/reference/*.csv` file with a schema's explicit column types
#' @noRd
stbam_read_reference_for_schema <- function(file_name, schema) {
  path <- file.path(stbam_project_root(), "data", "reference", file_name)
  if (!file.exists(path)) {
    stbam_abort("Reference table not found: ", path)
  }
  readr::read_csv(path, col_types = stbam_col_types(schema), progress = FALSE)
}

#' Populate a fresh evaluation's `inputs/` from `data/reference/` (ADR-003)
#' @noRd
stbam_populate_default_inputs <- function(evaluation_path) {
  today <- as.character(Sys.Date())
  for (category in names(STBAM_SET_CATEGORIES)) {
    info <- STBAM_SET_CATEGORIES[[category]]
    dir.create(stbam_category_dir(evaluation_path, category),
              recursive = TRUE, showWarnings = FALSE)
    # Every category folder gets a `_manifest.csv` immediately, even one
    # with zero sets (e.g. reporting_sets) -- so a reviewer browsing the
    # evaluation folder outside Shiny sees a consistent, self-explanatory
    # structure rather than an unexplained missing file (human instruction
    # #5: "Files remain understandable outside Shiny").
    readr::write_csv(stbam_empty_manifest(), stbam_manifest_path(evaluation_path, category))
    schema <- info$schema()
    if (is.null(schema$reference_file)) next  # e.g. reporting_sets -- starts empty
    df <- stbam_read_reference_for_schema(schema$reference_file, schema)
    manifest_row <- tibble::tibble(
      set_id = "default", set_name = "Assessment default",
      description = paste0("Copied wholesale from data/reference/",
                           schema$reference_file, " at evaluation creation."),
      source = "data/reference", date_or_version = today,
      status = "active", notes = ""
    )
    result <- write_named_set(evaluation_path, category, "default", df, manifest_row)
    if (!result$success) {
      stbam_abort("Failed to populate default `", category, "` set: ",
                  paste(result$errors, collapse = " "))
    }
  }

  use_result <- write_use_patterns(evaluation_path, stbam_empty_use_patterns(),
                                   check_referential_integrity = FALSE)
  if (!use_result$success) {
    stbam_abort("Failed to create empty use_patterns.csv: ",
                paste(use_result$errors, collapse = " "))
  }

  reference_dir <- file.path(evaluation_path, "inputs", "reference")
  dir.create(reference_dir, recursive = TRUE, showWarnings = FALSE)
  for (file_name in STBAM_REFERENCE_PROVENANCE_FILES) {
    src <- file.path(stbam_project_root(), "data", "reference", file_name)
    if (file.exists(src)) {
      file.copy(src, file.path(reference_dir, file_name), overwrite = TRUE)
    }
  }

  invisible(evaluation_path)
}

#' Create a new, complete evaluation folder
#'
#' @param evaluations_root The `evaluations/` directory (created if absent).
#' @param name The evaluation's folder name.
#' @return The new evaluation's path, invisibly.
#' @export
create_evaluation <- function(evaluations_root, name) {
  if (!stbam_is_evaluation_name_safe(name)) {
    stbam_abort("`name` is not a valid evaluation folder name: `", name, "`.")
  }
  if (!dir.exists(evaluations_root)) {
    dir.create(evaluations_root, recursive = TRUE)
  }
  evaluation_path <- file.path(evaluations_root, name)
  if (dir.exists(evaluation_path)) {
    stbam_abort("An evaluation named `", name, "` already exists at ", evaluation_path, ".")
  }

  dir.create(evaluation_path, recursive = TRUE)
  dir.create(file.path(evaluation_path, "inputs", "uses"), recursive = TRUE)
  stbam_create_outputs_tree(evaluation_path)
  stbam_populate_default_inputs(evaluation_path)

  invisible(evaluation_path)
}

#' List every evaluation under `evaluations_root`
#'
#' A folder counts as an evaluation if it directly contains both `inputs/`
#' and `outputs/` (ADR-002's exact two-subfolder structure) -- this is a
#' cheap structural check only, not a full schema validation (ADR-014's
#' picker screen needs to enumerate quickly without loading each
#' evaluation's full state).
#'
#' @param evaluations_root The `evaluations/` directory.
#' @return A tibble with `name`, `path`, `last_modified`, `n_runs` (one row
#'   per evaluation found; zero rows if `evaluations_root` does not exist or
#'   has no evaluations yet).
#' @export
list_evaluations <- function(evaluations_root) {
  empty <- tibble::tibble(name = character(), path = character(),
                          last_modified = as.POSIXct(character()),
                          n_runs = integer())
  if (!dir.exists(evaluations_root)) return(empty)

  candidates <- list.dirs(evaluations_root, recursive = FALSE, full.names = TRUE)
  is_evaluation <- vapply(candidates, function(p) {
    dir.exists(file.path(p, "inputs")) && dir.exists(file.path(p, "outputs"))
  }, logical(1))
  candidates <- candidates[is_evaluation]
  if (length(candidates) == 0L) return(empty)

  tibble::tibble(
    name = basename(candidates),
    path = candidates,
    last_modified = as.POSIXct(file.info(candidates)$mtime),
    n_runs = vapply(candidates, function(p) {
      runs_dir <- file.path(p, "outputs", "runs")
      if (!dir.exists(runs_dir)) return(0L)
      length(list.dirs(runs_dir, recursive = FALSE))
    }, integer(1))
  )
}

#' Open an existing evaluation (resolve and validate its path)
#'
#' @param evaluations_root The `evaluations/` directory.
#' @param name The evaluation's folder name.
#' @return The evaluation's path.
#' @export
open_evaluation <- function(evaluations_root, name) {
  path <- file.path(evaluations_root, name)
  if (!dir.exists(path) || !dir.exists(file.path(path, "inputs")) ||
      !dir.exists(file.path(path, "outputs"))) {
    stbam_abort("No evaluation named `", name, "` found under ", evaluations_root, ".")
  }
  path
}

#' Clone an evaluation's inputs under a new name
#'
#' Copies `inputs/` only, not run history (`shiny_information_architecture.md`
#' §2's stated default). The clone gets a fresh, empty `outputs/` tree.
#'
#' @param evaluations_root The `evaluations/` directory.
#' @param name The evaluation to clone.
#' @param new_name The new evaluation's name.
#' @return The new evaluation's path, invisibly.
#' @export
clone_evaluation <- function(evaluations_root, name, new_name) {
  source_path <- open_evaluation(evaluations_root, name)
  if (!stbam_is_evaluation_name_safe(new_name)) {
    stbam_abort("`new_name` is not a valid evaluation folder name: `", new_name, "`.")
  }
  dest_path <- file.path(evaluations_root, new_name)
  if (dir.exists(dest_path)) {
    stbam_abort("An evaluation named `", new_name, "` already exists at ", dest_path, ".")
  }

  dir.create(dest_path, recursive = TRUE)
  file.copy(file.path(source_path, "inputs"), dest_path, recursive = TRUE)
  stbam_create_outputs_tree(dest_path)

  invisible(dest_path)
}

#' Rename an evaluation
#'
#' @param evaluations_root The `evaluations/` directory.
#' @param name The evaluation's current folder name.
#' @param new_name The new folder name.
#' @return The renamed evaluation's path, invisibly.
#' @export
rename_evaluation <- function(evaluations_root, name, new_name) {
  source_path <- open_evaluation(evaluations_root, name)
  if (!stbam_is_evaluation_name_safe(new_name)) {
    stbam_abort("`new_name` is not a valid evaluation folder name: `", new_name, "`.")
  }
  dest_path <- file.path(evaluations_root, new_name)
  if (dir.exists(dest_path)) {
    stbam_abort("An evaluation named `", new_name, "` already exists at ", dest_path, ".")
  }
  ok <- file.rename(source_path, dest_path)
  if (!isTRUE(ok)) {
    stbam_abort("Failed to rename evaluation `", name, "` to `", new_name, "`.")
  }
  invisible(dest_path)
}

#' Delete an evaluation
#'
#' Requires `confirm = TRUE` -- an explicit safeguard against an accidental
#' call deleting a whole evaluation folder (this project's general
#' discipline around destructive, hard-to-reverse actions), on top of
#' whatever confirmation the Shiny picker screen itself presents.
#'
#' @param evaluations_root The `evaluations/` directory.
#' @param name The evaluation to delete.
#' @param confirm Must be `TRUE` for deletion to proceed.
#' @return `TRUE`, invisibly.
#' @export
delete_evaluation <- function(evaluations_root, name, confirm = FALSE) {
  path <- open_evaluation(evaluations_root, name)
  if (!isTRUE(confirm)) {
    stbam_abort("delete_evaluation() requires confirm = TRUE to delete `", name, "`.")
  }
  unlink(path, recursive = TRUE, force = TRUE)
  invisible(TRUE)
}
