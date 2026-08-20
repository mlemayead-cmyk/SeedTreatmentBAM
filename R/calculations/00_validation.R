# Input validation helpers for the calculation engine.
#
# The engine fails loudly. It never substitutes a guessed value for a missing
# or invalid scientific input (specification section 16).

#' Abort with a model error
#'
#' @param ... Message parts, pasted together.
#' @noRd
stbam_abort <- function(...) {
  stop(structure(
    class = c("stbam_error", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}

#' Validate a numeric model input
#'
#' @param x Value(s) to check.
#' @param name Parameter name used in error messages.
#' @param min Lowest permitted value (inclusive unless `exclusive_min`).
#' @param max Highest permitted value (inclusive).
#' @param exclusive_min If TRUE, `x` must be strictly greater than `min`.
#' @param allow_inf If TRUE, `Inf` is permitted (used for non-dissipating
#'   residues, specification section 7.2).
#' @return `x`, invisibly, if valid.
#' @noRd
check_numeric <- function(x, name, min = -Inf, max = Inf,
                          exclusive_min = FALSE, allow_inf = FALSE) {
  if (is.null(x) || length(x) == 0L) {
    stbam_abort("`", name, "` is required but was not supplied.")
  }
  # A bare `NA` is logical, so report it as a missing value rather than as a
  # type error: that is what the user actually did wrong.
  if (is.logical(x) && all(is.na(x))) {
    stbam_abort("`", name, "` contains missing values. The model does not ",
                "substitute defaults for missing scientific inputs.")
  }
  if (!is.numeric(x)) {
    stbam_abort("`", name, "` must be numeric, not ", class(x)[1], ".")
  }
  if (anyNA(x)) {
    stbam_abort("`", name, "` contains missing values. The model does not ",
                "substitute defaults for missing scientific inputs.")
  }
  if (!allow_inf && any(is.infinite(x))) {
    stbam_abort("`", name, "` contains non-finite values.")
  }

  finite <- x[is.finite(x)]
  if (exclusive_min) {
    if (any(finite <= min)) {
      stbam_abort("`", name, "` must be strictly greater than ", min,
                  "; smallest supplied value was ", min(finite), ".")
    }
  } else if (any(finite < min)) {
    stbam_abort("`", name, "` must be at least ", min,
                "; smallest supplied value was ", min(finite), ".")
  }
  if (any(finite > max)) {
    stbam_abort("`", name, "` must be at most ", max,
                "; largest supplied value was ", max(finite), ".")
  }
  invisible(x)
}

#' Validate a value against a closed set of permitted options
#' @noRd
check_choice <- function(x, name, choices) {
  if (is.null(x) || length(x) == 0L) {
    stbam_abort("`", name, "` is required but was not supplied.")
  }
  if (anyNA(x)) {
    stbam_abort("`", name, "` contains missing values.")
  }
  unknown <- setdiff(unique(as.character(x)), choices)
  if (length(unknown) > 0L) {
    stbam_abort("Unknown ", name, ": ", paste(sQuote(unknown), collapse = ", "),
                ". Permitted values: ", paste(choices, collapse = ", "), ".")
  }
  invisible(x)
}

#' Check that vectors can be recycled against one another
#'
#' Vectorised model functions accept either length-1 or common-length inputs.
#' Silent partial recycling is a classic source of misaligned scientific
#' results, so anything other than length 1 or the common length is an error.
#' @noRd
check_recyclable <- function(...) {
  args <- list(...)
  lengths <- vapply(args, length, integer(1))
  non_scalar <- lengths[lengths != 1L]
  if (length(non_scalar) == 0L) {
    return(invisible(1L))
  }
  target <- max(non_scalar)
  if (any(non_scalar != target)) {
    stbam_abort(
      "Inputs must be length 1 or a common length; received lengths ",
      paste(lengths, collapse = ", "), "."
    )
  }
  invisible(target)
}

#' Length-safe vectorised conditional
#'
#' `base::ifelse()` returns a result with the shape of its *test*. When the
#' test is scalar (for example a single half-life) and the branches are
#' vectors, it silently returns a single value that is then recycled. That is a
#' quiet, whole-column scientific error, so the engine never calls `ifelse()`
#' directly on possibly-scalar tests. This helper recycles the test and both
#' branches to their common length first.
#'
#' @param test Logical vector.
#' @param yes Values used where `test` is TRUE.
#' @param no Values used where `test` is FALSE.
#' @return A vector of the common length.
#' @noRd
stbam_ifelse <- function(test, yes, no) {
  n <- max(length(test), length(yes), length(no))
  if (n == 0L) {
    return(yes[0])
  }
  test <- rep_len(test, n)
  yes <- rep_len(yes, n)
  no <- rep_len(no, n)
  out <- no
  hit <- !is.na(test) & test
  out[hit] <- yes[hit]
  out[is.na(test)] <- NA
  out
}

#' Units recognised for a registered seed-treatment application rate
#' @export
STBAM_RATE_UNITS <- c("mg a.i./kg seed", "mg a.i./seed")

#' Planting methods recognised by the model
#' @export
STBAM_PLANTING_METHODS <- c("broadcast", "drill_spring", "drill_fall", "precision")

#' Molar mass ratio for the screening thiamethoxam to clothianidin conversion
#'
#' 249.68 / 291.7 (ASSUMPTION-003). Screening use only; the refined
#' seed-ingestion chain excludes quantitative clothianidin exposure
#' (ASSUMPTION-004).
#' @export
STBAM_CLOTHIANIDIN_MOLAR_RATIO <- 249.68 / 291.7

#' Level-of-concern threshold for risk quotients
#'
#' RQ >= this value indicates the effects metric is reached or exceeded. Kept
#' as a named constant, not a literal `1` scattered through plotting and
#' summary code, so a different LOC could be substituted for a metric where
#' one applies without hunting for hard-coded values. No effects metric in
#' the current register uses a different LOC.
#' @export
STBAM_DEFAULT_LOC <- 1

#' Specification/model version, for figure and export provenance
#'
#' Matches the version at the top of the change-control table in
#' `docs/scientific_model_specification.md`. Update both together.
#' @export
STBAM_MODEL_VERSION <- "1.2.0"
