# Parameter sets: assessment baseline plus a protected override layer.
#
# Specification section 12. A Shiny experiment must never change what
# constitutes the official assessment scenario. Overrides live in their own
# layer, carry provenance, and are labelled wherever they are used.

#' Permitted parameter status values
#' @export
STBAM_PARAMETER_STATUS <- c(
  "ASSESSMENT_DEFAULT", "USER_OVERRIDE", "UPDATED_SOURCE",
  "PROVISIONAL", "REVIEWED"
)

#' Parameters that may be overridden
#'
#' Each entry gives the unit, permitted range and a short description used by
#' the interface.
#' @export
STBAM_OVERRIDABLE <- list(
  tkw_g_per_1000              = list(unit = "g/1000 seeds", min = 1e-6, max = Inf,
                                     label = "Thousand-seed weight"),
  seeds_per_ha                = list(unit = "seeds/ha", min = 0, max = Inf,
                                     label = "Seeds planted"),
  seeding_rate_kg_per_ha      = list(unit = "kg seed/ha", min = 0, max = Inf,
                                     label = "Seeding rate (mass basis)"),
  application_rate            = list(unit = "rate unit", min = 0, max = Inf,
                                     label = "Seed treatment rate"),
  surface_seed_fraction       = list(unit = "fraction", min = 0, max = 1,
                                     label = "Proportion of seed on the surface"),
  surface_seed_dt50_days      = list(unit = "days", min = 1e-6, max = Inf,
                                     label = "Surface-seed disappearance DT50"),
  residue_dt50_days           = list(unit = "days", min = 1e-6, max = Inf,
                                     label = "Residue dissipation DT50"),
  body_weight_g               = list(unit = "g", min = 1e-6, max = Inf,
                                     label = "Body weight"),
  food_intake_g_dw_per_day    = list(unit = "g dw/day", min = 0, max = Inf,
                                     label = "Food ingestion rate"),
  msa_m2                      = list(unit = "m2", min = 1e-6, max = Inf,
                                     label = "Maximum search area"),
  effects_metric              = list(unit = "mg a.i./kg bw/d", min = 1e-12, max = Inf,
                                     label = "Effects metric")
)

#' Create a parameter set
#'
#' @param baseline An `stbam_baseline` from [load_baseline].
#' @param name A short label for this parameter set.
#' @return An `stbam_parameter_set` with an empty override layer.
#' @export
parameter_set <- function(baseline, name = "Assessment baseline") {
  if (!inherits(baseline, "stbam_baseline")) {
    stbam_abort("`baseline` must come from load_baseline().")
  }
  structure(
    list(
      name = name,
      baseline = baseline,
      overrides = empty_override_table(),
      created_at = Sys.time()
    ),
    class = c("stbam_parameter_set", "list")
  )
}

#' @noRd
empty_override_table <- function() {
  tibble::tibble(
    parameter = character(),
    scope = character(),
    value = numeric(),
    unit = character(),
    baseline_value = numeric(),
    status = character(),
    source = character(),
    note = character(),
    set_at = as.POSIXct(character())
  )
}

#' Record a parameter override
#'
#' Overrides never modify the baseline. Re-setting the same parameter and scope
#' replaces the previous override rather than accumulating duplicates.
#'
#' @param params An `stbam_parameter_set`.
#' @param parameter Parameter name; must be in [STBAM_OVERRIDABLE].
#' @param value New value.
#' @param scope Where the override applies, e.g. a crop name, a receptor id, or
#'   `"global"`.
#' @param baseline_value The value being replaced, for the change log.
#' @param status One of [STBAM_PARAMETER_STATUS]; not `ASSESSMENT_DEFAULT`.
#' @param source Provenance for the new value.
#' @param note Free text.
#' @return The updated parameter set.
#' @export
set_override <- function(params, parameter, value, scope = "global",
                         baseline_value = NA_real_,
                         status = "USER_OVERRIDE", source = "", note = "") {
  if (!inherits(params, "stbam_parameter_set")) {
    stbam_abort("`params` must be an stbam_parameter_set.")
  }
  check_choice(parameter, "parameter", names(STBAM_OVERRIDABLE))
  check_choice(status, "status", setdiff(STBAM_PARAMETER_STATUS,
                                         "ASSESSMENT_DEFAULT"))
  spec <- STBAM_OVERRIDABLE[[parameter]]
  check_numeric(value, parameter, min = spec$min, max = spec$max)
  if (length(value) != 1L) {
    stbam_abort("An override must be a single value; received ", length(value), ".")
  }

  keep <- !(params$overrides$parameter == parameter &
              params$overrides$scope == scope)
  params$overrides <- rbind(
    params$overrides[keep, , drop = FALSE],
    tibble::tibble(
      parameter = parameter, scope = scope, value = as.numeric(value),
      unit = spec$unit, baseline_value = as.numeric(baseline_value),
      status = status, source = as.character(source),
      note = as.character(note), set_at = Sys.time()
    )
  )
  params
}

#' Remove one override, or all of them
#'
#' @param params An `stbam_parameter_set`.
#' @param parameter Parameter to clear, or `NULL` to reset everything.
#' @param scope Scope to clear, or `NULL` (the default) to clear `parameter`
#'   at every scope.
#' @return The updated parameter set.
#' @export
clear_override <- function(params, parameter = NULL, scope = NULL) {
  if (is.null(parameter)) {
    params$overrides <- empty_override_table()
    return(params)
  }
  # Built as two explicit, always-full-length logical vectors rather than one
  # expression combining `is.null(scope)` with a vector comparison: comparing
  # a character vector against NULL yields a zero-length result in R, which
  # previously collapsed the whole `keep` vector to length 0 and made this
  # documented `scope = NULL` call unusable (tibble subsetting rejects a
  # zero-length logical index).
  matches_parameter <- params$overrides$parameter == parameter
  matches_scope <- if (is.null(scope)) {
    rep(TRUE, nrow(params$overrides))
  } else {
    params$overrides$scope == scope
  }
  keep <- !(matches_parameter & matches_scope)
  params$overrides <- params$overrides[keep, , drop = FALSE]
  params
}

#' Reset a parameter set to the assessment baseline
#' @export
reset_to_baseline <- function(params) {
  clear_override(params)
}

#' Look up the effective value of a parameter
#'
#' Returns the override if one applies to `scope`, otherwise a global override,
#' otherwise `default`.
#'
#' @param params An `stbam_parameter_set`.
#' @param parameter Parameter name.
#' @param scope Scope to resolve, e.g. a crop name.
#' @param default Baseline value to fall back to.
#' @return A list with `value` and `status`.
#' @export
effective_value <- function(params, parameter, scope = "global", default) {
  overrides <- params$overrides
  hit <- overrides[overrides$parameter == parameter & overrides$scope == scope, ]
  if (nrow(hit) == 0L) {
    hit <- overrides[overrides$parameter == parameter &
                       overrides$scope == "global", ]
  }
  if (nrow(hit) == 0L) {
    return(list(value = default, status = "ASSESSMENT_DEFAULT"))
  }
  list(value = hit$value[[nrow(hit)]], status = hit$status[[nrow(hit)]])
}

#' Does this parameter set differ from the assessment baseline?
#' @export
has_overrides <- function(params) nrow(params$overrides) > 0L

#' Export a parameter set's overrides to CSV
#'
#' Exports only the override layer. The baseline is reproducible from the
#' source workbooks and is not duplicated into scenario files.
#'
#' @param params An `stbam_parameter_set`.
#' @param path Destination CSV path.
#' @return `path`, invisibly.
#' @export
export_scenario_config <- function(params, path) {
  out <- params$overrides
  out$scenario_name <- params$name
  readr::write_csv(out, path)
  invisible(path)
}

#' Reload a previously exported scenario configuration
#'
#' @param baseline An `stbam_baseline`.
#' @param path A CSV written by [export_scenario_config].
#' @return An `stbam_parameter_set`.
#' @export
import_scenario_config <- function(baseline, path) {
  if (!file.exists(path)) {
    stbam_abort("Scenario configuration not found: ", path)
  }
  saved <- readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
  name <- if ("scenario_name" %in% names(saved) && nrow(saved) > 0L) {
    saved$scenario_name[[1]]
  } else {
    basename(path)
  }
  params <- parameter_set(baseline, name = name)
  if (nrow(saved) == 0L) {
    return(params)
  }
  for (i in seq_len(nrow(saved))) {
    params <- set_override(
      params,
      parameter = saved$parameter[[i]],
      value = saved$value[[i]],
      scope = saved$scope[[i]],
      baseline_value = if ("baseline_value" %in% names(saved)) {
        saved$baseline_value[[i]]
      } else {
        NA_real_
      },
      status = saved$status[[i]],
      source = if ("source" %in% names(saved)) {
        saved$source[[i]] %||% ""
      } else {
        ""
      },
      note = if ("note" %in% names(saved)) saved$note[[i]] %||% "" else ""
    )
  }
  params
}

#' @noRd
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || is.na(x)) y else x

#' @export
print.stbam_parameter_set <- function(x, ...) {
  cat(sprintf("<stbam parameter set: %s>\n", x$name))
  if (!has_overrides(x)) {
    cat("  assessment baseline, no overrides\n")
  } else {
    cat(sprintf("  %d override(s):\n", nrow(x$overrides)))
    for (i in seq_len(nrow(x$overrides))) {
      row <- x$overrides[i, ]
      cat(sprintf("    %-24s %-16s %g %s [%s]\n", row$parameter, row$scope,
                  row$value, row$unit, row$status))
    }
  }
  invisible(x)
}
