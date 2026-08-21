# Phase 1: named-set folder/manifest read-write logic (ADR-004).
#
# docs/planning/folder_and_input_schema.md §2. One category (`seeding_sets`)
# was built and tested first as the template (readiness-review amendment to
# implementation_phases_proposal.md Phase 1); this file's functions are
# category-agnostic by construction (driven by `STBAM_SET_CATEGORIES` /
# `50_schema_registry.R`), so the same code is what "replicating the pattern"
# to the remaining four categories actually means here -- there is no
# separate per-category implementation to write.
#
# Validate-before-replace (I15, ADR-006): `write_named_set()` never writes a
# byte to disk unless validation of the *complete* proposed content passes.
# A failed validation leaves the previously saved file completely untouched.

#' Is `id` a safe, plain filename component?
#'
#' folder_and_input_schema.md §2.1: `set_id` must be "filename-safe."
#' @export
stbam_is_filename_safe <- function(id) {
  is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id) &&
    grepl("^[A-Za-z0-9_-]+$", id)
}

#' Build an explicit `readr` column-type spec from a schema
#'
#' **Deliberately never lets `readr` guess column types.** `readr::read_csv()`
#' without an explicit `col_types` guesses `integer` for a numeric column
#' whose *visible* values all happen to be whole numbers, and `double`
#' otherwise -- a guess driven by incidental formatting, not by the column's
#' actual scientific type. Because every numeric column in this schema
#' registry represents a continuous scientific quantity (never a count with
#' integer semantics), every numeric column is forced to `col_double()`
#' unconditionally. This closes the "integer vs. double representation
#' alternates by entry path" risk investigated for Phase 1 (see the
#' Phase 1 completion report) at the schema/read boundary, rather than by
#' touching the Phase 0 content-hash primitive itself.
#'
#' @param schema A schema object from `50_schema_registry.R`.
#' @return A `readr::cols()` specification.
#' @noRd
stbam_col_types <- function(schema) {
  specs <- lapply(schema$columns, function(col) {
    switch(col$type,
      character = readr::col_character(),
      numeric = readr::col_double(),
      logical = readr::col_logical()
    )
  })
  names(specs) <- vapply(schema$columns, `[[`, character(1), "name")
  do.call(readr::cols, specs)
}

#' Path to a named-set category's folder inside an evaluation
#' @export
stbam_category_dir <- function(evaluation_path, category) {
  info <- STBAM_SET_CATEGORIES[[category]]
  if (is.null(info)) {
    stbam_abort("Unknown named-set category: ", category, ". Known categories: ",
                paste(names(STBAM_SET_CATEGORIES), collapse = ", "), ".")
  }
  file.path(evaluation_path, "inputs", "assumptions", info$path)
}

#' Path to a specific named set's CSV file
#' @export
stbam_set_path <- function(evaluation_path, category, set_id) {
  file.path(stbam_category_dir(evaluation_path, category), paste0(set_id, ".csv"))
}

#' Path to a category's manifest CSV
#' @export
stbam_manifest_path <- function(evaluation_path, category) {
  file.path(stbam_category_dir(evaluation_path, category), "_manifest.csv")
}

#' An empty, correctly-typed manifest tibble
#' @noRd
stbam_empty_manifest <- function() {
  tibble::tibble(
    set_id = character(), set_name = character(), description = character(),
    source = character(), date_or_version = character(), status = character(),
    notes = character()
  )
}

#' List the named sets registered in a category's manifest
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param category One of `names(STBAM_SET_CATEGORIES)`.
#' @return A tibble (the manifest), possibly zero rows. Never errors if the
#'   category has no sets yet -- an evaluation-freshly-created,
#'   not-yet-populated `reporting_sets/` is a valid state
#'   (`50_schema_registry.R`'s note on `stbam_schema_reporting_sets()`).
#' @export
list_named_sets <- function(evaluation_path, category) {
  path <- stbam_manifest_path(evaluation_path, category)
  if (!file.exists(path)) {
    return(stbam_empty_manifest())
  }
  readr::read_csv(path, col_types = stbam_col_types(stbam_manifest_schema()),
                  progress = FALSE)
}

#' Read one named set's data (not its manifest row)
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param category One of `names(STBAM_SET_CATEGORIES)`.
#' @param set_id The set's stable identifier.
#' @return A tibble.
#' @export
read_named_set <- function(evaluation_path, category, set_id) {
  info <- STBAM_SET_CATEGORIES[[category]]
  path <- stbam_set_path(evaluation_path, category, set_id)
  if (!file.exists(path)) {
    stbam_abort("Named set not found: category `", category, "`, set_id `",
                set_id, "` (expected at ", path, ").")
  }
  readr::read_csv(path, col_types = stbam_col_types(info$schema()), progress = FALSE)
}

#' Write (create or replace) one named set's data and manifest entry
#'
#' Validate-before-replace (I15): both the set's data (against its
#' category's schema) and the resulting manifest (with this set's row
#' upserted) are validated *before anything is written*. If either check
#' fails, this function writes nothing and returns the failure -- the
#' previously saved set file and manifest, if any, are left byte-identical.
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param category One of `names(STBAM_SET_CATEGORIES)`.
#' @param set_id The set's stable, filename-safe identifier.
#' @param df The set's complete data (a data.frame/tibble).
#' @param manifest_row A one-row data.frame/tibble with the manifest columns
#'   (`set_name` required; the rest optional -- see `stbam_manifest_schema()`).
#'   `set_id` is filled in automatically from the `set_id` argument if not
#'   already present.
#' @return A list: `success` (logical), `errors` (character vector, empty on
#'   success).
#' @export
write_named_set <- function(evaluation_path, category, set_id, df, manifest_row) {
  info <- STBAM_SET_CATEGORIES[[category]]
  if (is.null(info)) {
    return(list(success = FALSE, errors = paste0("Unknown named-set category: ", category, ".")))
  }
  if (!stbam_is_filename_safe(set_id)) {
    return(list(success = FALSE, errors = paste0(
      "`set_id` must be filename-safe (letters, digits, `_`, `-` only); received `",
      set_id, "`.")))
  }

  data_check <- validate_table(df, info$schema())
  if (!data_check$valid) {
    return(list(success = FALSE, errors = data_check$errors))
  }

  if (!"set_id" %in% names(manifest_row) || is.na(manifest_row$set_id[[1]])) {
    manifest_row$set_id <- set_id
  } else if (!identical(manifest_row$set_id[[1]], set_id)) {
    return(list(success = FALSE, errors = paste0(
      "manifest_row$set_id (`", manifest_row$set_id[[1]],
      "`) does not match the set_id argument (`", set_id, "`).")))
  }
  for (col in setdiff(names(stbam_empty_manifest()), names(manifest_row))) {
    manifest_row[[col]] <- NA_character_
  }
  manifest_row <- manifest_row[names(stbam_empty_manifest())]

  existing_manifest <- list_named_sets(evaluation_path, category)
  updated_manifest <- existing_manifest[existing_manifest$set_id != set_id, , drop = FALSE]
  updated_manifest <- rbind(updated_manifest, manifest_row)

  manifest_check <- validate_manifest(updated_manifest)
  if (!manifest_check$valid) {
    return(list(success = FALSE, errors = manifest_check$errors))
  }

  dir <- stbam_category_dir(evaluation_path, category)
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)

  readr::write_csv(df, stbam_set_path(evaluation_path, category, set_id))
  readr::write_csv(updated_manifest, stbam_manifest_path(evaluation_path, category))

  list(success = TRUE, errors = character())
}

#' Delete a named set (data file + manifest row)
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param category One of `names(STBAM_SET_CATEGORIES)`.
#' @param set_id The set's stable identifier.
#' @return `TRUE`, invisibly.
#' @export
delete_named_set <- function(evaluation_path, category, set_id) {
  path <- stbam_set_path(evaluation_path, category, set_id)
  if (file.exists(path)) file.remove(path)
  manifest <- list_named_sets(evaluation_path, category)
  manifest <- manifest[manifest$set_id != set_id, , drop = FALSE]
  readr::write_csv(manifest, stbam_manifest_path(evaluation_path, category))
  invisible(TRUE)
}

#' All crop names appearing across every seeding set in an evaluation
#'
#' Used for `use_patterns.csv` / `reporting_sets` referential-integrity
#' checks (folder_and_input_schema.md §4). An evaluation with more than one
#' seeding set (ADR-004) is checked against the union across all of them,
#' since Phase 1 does not yet have a formal "currently active set" concept
#' (that belongs to run creation, `run_lifecycle_and_validation.md` §2 step
#' 1 -- Phase 3).
#' @export
stbam_known_crops <- function(evaluation_path) {
  manifest <- list_named_sets(evaluation_path, "seeding_sets")
  if (nrow(manifest) == 0L) return(character())
  crops <- lapply(manifest$set_id, function(id) {
    read_named_set(evaluation_path, "seeding_sets", id)$crop
  })
  unique(unlist(crops, use.names = FALSE))
}
