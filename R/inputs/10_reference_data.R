# Loading the canonical reference data.
#
# The reference tables in data/reference are produced from the immutable source
# workbooks by scripts/extract_reference_data.py. They are the assessment
# baseline and are never written to by the application.

#' Path to the project root
#' @noRd
stbam_project_root <- function() {
  root <- getOption("stbam.project_root", default = NULL)
  if (!is.null(root)) {
    return(normalizePath(root, winslash = "/", mustWork = TRUE))
  }
  normalizePath(file.path(dirname(dirname(stbam_source_dir())), "."),
                winslash = "/", mustWork = TRUE)
}

#' Directory holding the R source tree, discovered at load time
#' @noRd
stbam_source_dir <- function() {
  getOption("stbam.source_dir", default = file.path(getwd(), "R"))
}

#' Read a reference table
#' @noRd
read_reference <- function(name) {
  path <- file.path(stbam_project_root(), "data", "reference", name)
  if (!file.exists(path)) {
    stbam_abort("Reference table not found: ", path,
                "\nRun: python scripts/extract_reference_data.py")
  }
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

#' Load the complete assessment baseline
#'
#' Returns the immutable assessment defaults. Nothing in the application
#' modifies this object; user changes are applied as a separate override layer
#' (see [apply_overrides]).
#'
#' @return A list of tibbles, class `stbam_baseline`.
#' @export
load_baseline <- function() {
  baseline <- list(
    crops = read_reference("crop_seeding_parameters.csv"),
    planting_methods = read_reference("planting_method_parameters.csv"),
    receptors = read_reference("receptor_parameters.csv"),
    fir_regressions = read_reference("fir_regressions.csv"),
    effects_metrics = read_reference("effects_metrics.csv"),
    dissipation = read_reference("dissipation_parameters.csv"),
    scenarios = read_reference("scenario_definitions.csv"),
    source_manifest = read_reference("source_manifest.csv")
  )
  structure(baseline, class = c("stbam_baseline", "list"))
}

#' Dissipation default by name
#'
#' @param baseline An `stbam_baseline`.
#' @param parameter Parameter name, e.g. `"residue_dt50_days"`.
#' @return The default value.
#' @export
dissipation_default <- function(baseline, parameter) {
  row <- baseline$dissipation[baseline$dissipation$parameter == parameter, ]
  if (nrow(row) != 1L) {
    stbam_abort("Dissipation parameter not found in the baseline: ", parameter)
  }
  row$value[[1]]
}

#' @export
print.stbam_baseline <- function(x, ...) {
  cat("<stbam assessment baseline>\n")
  cat(sprintf("  crops              %d\n", nrow(x$crops)))
  cat(sprintf("  planting methods   %d\n", nrow(x$planting_methods)))
  cat(sprintf("  receptors          %d\n", nrow(x$receptors)))
  cat(sprintf("  effects metrics    %d\n", nrow(x$effects_metrics)))
  cat(sprintf("  crop x rate rows   %d\n", nrow(x$scenarios)))
  cat(sprintf("  source workbooks   %d\n", nrow(x$source_manifest)))
  invisible(x)
}
