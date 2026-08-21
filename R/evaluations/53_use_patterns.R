# Phase 1: use_patterns.csv read-write logic (ADR-005).
#
# docs/planning/folder_and_input_schema.md §3. A single normalized table per
# evaluation (not a named-set category) -- one row per atomic use condition,
# with a crop/rate use spanning several planting methods stored as multiple
# rows sharing one `use_id`.

#' Path to `inputs/uses/use_patterns.csv` inside an evaluation
#' @export
stbam_use_patterns_path <- function(evaluation_path) {
  file.path(evaluation_path, "inputs", "uses", "use_patterns.csv")
}

#' An empty, correctly-typed use_patterns tibble
#' @noRd
stbam_empty_use_patterns <- function() {
  tibble::tibble(
    use_id = character(), crop = character(), rate_value = double(),
    rate_unit = character(), rate_level = character(),
    planting_method = character(), workbook = character(),
    product_identifier = character(), region = character(),
    target_pest = character(), notes = character()
  )
}

#' Read `use_patterns.csv`
#'
#' @param evaluation_path Path to an evaluation folder.
#' @return A tibble. If the file does not yet exist, returns a zero-row
#'   table with the correct schema (a freshly-created evaluation has an
#'   empty, not missing, use_patterns.csv -- see `create_evaluation()`).
#' @export
read_use_patterns <- function(evaluation_path) {
  path <- stbam_use_patterns_path(evaluation_path)
  if (!file.exists(path)) return(stbam_empty_use_patterns())
  readr::read_csv(path, col_types = stbam_col_types(stbam_schema_use_patterns()),
                  progress = FALSE)
}

#' Write (replace) `use_patterns.csv`
#'
#' Validate-before-replace (I15): the complete proposed table is validated,
#' including referential integrity against the evaluation's current seeding
#' sets, before anything is written. A failed validation leaves the
#' previously saved file untouched.
#'
#' @param evaluation_path Path to an evaluation folder.
#' @param df The complete, replacement use_patterns table.
#' @param check_referential_integrity If `TRUE` (default), every `crop`
#'   value in `df` must exist in at least one of the evaluation's seeding
#'   sets (`stbam_known_crops()`).
#' @return A list: `success` (logical), `errors` (character vector).
#' @export
write_use_patterns <- function(evaluation_path, df, check_referential_integrity = TRUE) {
  known_crops <- if (check_referential_integrity) {
    stbam_known_crops(evaluation_path)
  } else {
    NULL
  }
  check <- validate_use_patterns(df, known_crops = known_crops)
  if (!check$valid) {
    return(list(success = FALSE, errors = check$errors))
  }

  dir <- dirname(stbam_use_patterns_path(evaluation_path))
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  readr::write_csv(df, stbam_use_patterns_path(evaluation_path))
  list(success = TRUE, errors = character())
}
