# Phase 0 shared infrastructure: general-purpose peak-finding utility.
#
# Architectural requirement (ADR-009, docs/planning/assessment_workspace_
# architecture.md): "peak is a calculated argmax, not permanently synonymous
# with day 0." This file performs a true argmax search over an
# already-evaluated day/value series (or, via stbam_peak_over_function(), a
# supplied function evaluated over a day grid) and never special-cases day 0
# or assumes monotonic decline.
#
# This file contains no scientific calculation of its own. It consumes
# values a caller has already computed -- typically from the existing,
# unchanged build_daily_timecourse() -- and performs only a generic argmax
# search plus deterministic tie-breaking. Nothing in R/calculations/ is read
# or modified by this file. It does not change, and must never be used to
# second-guess, the current model's own result: for the current,
# independently-audited model (whose dose/RQ trajectories decline
# monotonically from sowing, per docs/independent_engine_audit.md and
# tests/testthat/test-06-invariants.R invariants 1-2), the expected,
# correct output of this utility is peak day 0 -- that is not a defect.

#' Find the day at which a day-dependent series peaks
#'
#' A general-purpose argmax search over a `day`/`value` series. Does not
#' assume the maximum occurs at day 0, or anywhere in particular -- this is
#' what makes it suitable for a future model version with non-monotonic
#' time-dependent behaviour (ADR-009), even though the current model is
#' expected to still resolve to day 0 in every case.
#'
#' **Non-finite handling.** `NA`, `NaN`, `Inf`, and `-Inf` entries in `value`
#' are ignored when searching for the maximum, as if that day had not been
#' evaluated. If every entry is non-finite, the result is entirely `NA`
#' (day, value, and tie fields), never an arbitrary day.
#'
#' **Tie-breaking.** When more than one day shares the maximum value, the
#' **earliest** (smallest) tied day is returned as `day`. This is a
#' deliberate, documented choice -- not left arbitrary -- so a reviewer does
#' not need to infer the rule from behaviour. `tied` reports whether a tie
#' occurred and `n_tied` how many days share the maximum, so a caller that
#' needs the full tied set is not left to rediscover it by re-scanning the
#' series.
#'
#' @param day Numeric vector of day values. Not required to be sorted, to
#'   start at 0, or to be free of duplicates.
#' @param value Numeric vector of the day-dependent quantity evaluated at
#'   each `day`; must be the same length as `day`. May contain non-finite
#'   values (see above); `day` itself may not.
#' @return A list with elements:
#'   \item{day}{The peak day (the smallest day among ties). `NA_real_` if no
#'     finite value was supplied.}
#'   \item{value}{The peak value. `NA_real_` if no finite value was
#'     supplied.}
#'   \item{tied}{`TRUE` if more than one day shares the maximum value,
#'     `FALSE` otherwise (including the no-finite-value case).}
#'   \item{n_tied}{Number of days sharing the maximum value (`0` if none is
#'     finite, `1` if the maximum is unique).}
#' @export
stbam_find_peak <- function(day, value) {
  check_numeric(day, "day", allow_inf = FALSE)
  if (is.null(value) || length(value) == 0L) {
    stbam_abort("`value` is required but was not supplied.")
  }
  if (!is.numeric(value)) {
    stbam_abort("`value` must be numeric, not ", class(value)[1], ".")
  }
  if (length(day) != length(value)) {
    stbam_abort("`day` and `value` must be the same length; received ",
                length(day), " and ", length(value), ".")
  }

  finite <- is.finite(value)
  if (!any(finite)) {
    return(list(day = NA_real_, value = NA_real_, tied = FALSE, n_tied = 0L))
  }

  candidate_day <- day[finite]
  candidate_value <- value[finite]
  peak_value <- max(candidate_value)
  at_peak <- candidate_value == peak_value
  # n_tied counts distinct DAYS at the maximum, per this function's own
  # documentation -- not raw rows. `day` is explicitly permitted to contain
  # duplicates (e.g. more than one row for the same day), and two rows for
  # the *same* day both hitting the maximum is not a tie between different
  # days (independent-review finding).
  n_tied <- length(unique(candidate_day[at_peak]))

  list(
    day = min(candidate_day[at_peak]),
    value = peak_value,
    tied = n_tied > 1L,
    n_tied = n_tied
  )
}

#' Find the peak of a day-dependent function by evaluating it over a day grid
#'
#' Thin convenience wrapper around [stbam_find_peak()] for the common case
#' where the caller has a function of day -- for example, a closure over one
#' scenario/receptor/metric/diet-fraction context that reads from the
#' **unchanged** `build_daily_timecourse()` machinery -- rather than an
#' already-evaluated series. This function performs no scientific
#' calculation itself: it only calls `f` once per requested day and searches
#' the resulting series exactly as [stbam_find_peak()] does.
#'
#' @param f A function of one numeric argument (day), returning a single
#'   numeric value -- or a bare, untyped `NA` (as opposed to a string, a
#'   logical `TRUE`/`FALSE`, or a vector of length != 1) is also accepted,
#'   treated identically to `NA_real_`, since it is R's most idiomatic way
#'   to express "not evaluated for this day" (e.g. `if (nrow(row) == 0) NA
#'   else row$rq`) and [stbam_find_peak()] already documents `NA` as a
#'   legitimate, ignored sentinel.
#' @param days Numeric vector of days to evaluate `f` at. The result is
#'   exactly as fine or coarse as this grid -- choosing a sufficiently fine
#'   grid for the scenario's relevant time horizon is the caller's
#'   responsibility (`result_architecture_and_aggregation.md` §2), not this
#'   function's.
#' @return Same shape as [stbam_find_peak()].
#' @export
stbam_peak_over_function <- function(f, days) {
  if (!is.function(f)) {
    stbam_abort("`f` must be a function of one argument (day).")
  }
  check_numeric(days, "days", allow_inf = FALSE)
  # `f(d)` is required to already return a single numeric value (or a bare
  # NA, see @param f above) -- this does NOT coerce via as.numeric(), which
  # would silently turn a malformed result (e.g. a non-numeric string) into
  # NA rather than failing loudly, contrary to this project's validation
  # philosophy (independent-review finding). The bare-NA carve-out was added
  # after a second review pass found the initial fix rejected R's own
  # untyped `NA` literal (class "logical"), which is not the malformed input
  # this check exists to catch.
  values <- vapply(days, function(d) {
    v <- f(d)
    if (length(v) != 1L) {
      stbam_abort("`f` must return a single numeric value for each day; got ",
                  "length ", length(v), " for day ", d, ".")
    }
    is_bare_na <- is.logical(v) && is.na(v)
    if (!is.numeric(v) && !is_bare_na) {
      stbam_abort("`f` must return a single numeric value for each day; got ",
                  class(v)[1], " for day ", d, ".")
    }
    if (is_bare_na) NA_real_ else v
  }, numeric(1))
  stbam_find_peak(days, values)
}
