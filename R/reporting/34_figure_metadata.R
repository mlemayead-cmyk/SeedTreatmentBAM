# Canonical figure metadata and human-readable labels.
#
# A figure exported from Shiny must be understandable without access to the
# Shiny interface. This file gathers everything a reviewer needs to
# interpret a figure -- scenario, agronomy, fate parameters, receptor,
# effects metric, provenance -- into one structure, built from canonical
# model data rather than hand-maintained per plot. The same structure feeds
# the plot subtitle/caption, the Shiny "current assumptions" panel, and
# (later) Word export.

#' Human-readable label for one scenario row
#'
#' Replaces an internal id such as
#' `small_cereals|Barley|high|300|mg a.i./kg seed|broadcast|high|high_tkw`
#' with a label a reader
#' can interpret directly. The internal id remains available as
#' `scenario_id` wherever the row itself is available.
#'
#' @param row One row of [build_scenario_inputs], [build_scenario_summary]
#'   or [build_daily_timecourse] output.
#' @return A single character string.
#' @export
format_scenario_label <- function(row) {
  bound_label <- switch(
    row$seed_mass_bound[[1]],
    low_tkw = "low TKW",
    high_tkw = "high TKW",
    row$seed_mass_bound[[1]]
  )
  seeding_label <- switch(
    row$seeding_rate_bound[[1]],
    low = "low seeding rate",
    high = "high seeding rate",
    row$seeding_rate_bound[[1]]
  )
  sprintf(
    "%s — %s treatment rate — %s — %s / %s scenario",
    row$crop[[1]], tolower(row$rate_level[[1]]),
    row$planting_method_label[[1]], seeding_label, bound_label
  )
}

#' Human-readable label for an effects metric
#'
#' Replaces an internal id such as `bird_acute_screening` with a label such
#' as `"Bird acute screening — 43.1 mg a.i./kg bw/day"`.
#'
#' @param taxon `"bird"` or `"mammal"`.
#' @param duration_class `"acute"` or `"chronic"`.
#' @param metric_role `"SCREENING"`, `"REFINED"` or `"REFINED_ADDITIONAL"`.
#' @param effects_metric The numeric effects-metric value.
#' @param unit Effects-metric unit. Defaults to the model's registered unit
#'   (`effects_metrics.csv$unit`, `"mg a.i./kg bw/d"`) -- pass the row's own
#'   `unit` explicitly if calling this for a different register in future,
#'   so the label never silently disagrees with the metric's own provenance
#'   text (independent review finding, check 7).
#' @return A single character string.
#' @export
format_metric_label <- function(taxon, duration_class, metric_role,
                                effects_metric, unit = "mg a.i./kg bw/d") {
  role_label <- switch(
    metric_role,
    SCREENING = "screening",
    REFINED = "refined",
    REFINED_ADDITIONAL = "refined additional",
    tolower(metric_role)
  )
  sprintf("%s %s %s — %s %s", tools::toTitleCase(taxon), duration_class,
          role_label, fmt_sig(effects_metric), unit)
}

#' Human-readable label for a receptor
#'
#' @param size_class `"small"`, `"medium"` or `"large"`.
#' @param taxon `"bird"` or `"mammal"`.
#' @param body_weight_g Body weight, g.
#' @return A single character string, e.g. `"Small bird (20 g)"`.
#' @export
format_receptor_label <- function(size_class, taxon, body_weight_g) {
  sprintf("%s %s (%s g)", tools::toTitleCase(size_class), taxon,
          fmt_sig(body_weight_g))
}

#' @noRd
msa_policy_note <- function(taxon, msa_term) {
  if (identical(taxon, "bird")) {
    paste(
      "Birds use the short-term MSA for both acute and",
      "chronic/reproductive characterization; the source assessment",
      "states a long-term MSA was not considered for birds (assessment",
      "paragraph MAIN-P000209)."
    )
  } else if (identical(msa_term, "long")) {
    paste(
      "Mammalian chronic/reproductive characterization uses the long-term",
      "MSA; the source assessment attributes mammalian reproductive",
      "effects to prolonged parental exposure (assessment paragraph",
      "MAIN-P000209)."
    )
  } else {
    paste(
      "Mammalian acute characterization uses the short-term MSA",
      "(assessment paragraph MAIN-P000209)."
    )
  }
}

#' @noRd
format_override_summary <- function(params) {
  if (!has_overrides(params)) return(NULL)
  ov <- params$overrides
  lines <- sprintf(
    "%s (%s): %s -> %s %s [%s]",
    ov$parameter, ov$scope, fmt_sig(ov$baseline_value), fmt_sig(ov$value),
    ov$unit, ov$status
  )
  paste(lines, collapse = "; ")
}

#' @noRd
read_project_git_commit <- function(root = getOption("stbam.project_root", getwd())) {
  cached <- getOption("stbam.git_commit", NULL)
  if (!is.null(cached)) return(cached)

  read_first_line <- function(path) {
    tryCatch(
      trimws(readLines(path, n = 1L, warn = FALSE)),
      error = function(e) NA_character_
    )
  }
  head_path <- file.path(root, ".git", "HEAD")
  if (!file.exists(head_path)) return(NA_character_)
  head <- read_first_line(head_path)
  if (is.na(head)) return(NA_character_)
  if (!startsWith(head, "ref: ")) {
    commit <- substr(head, 1L, 12L)
    options(stbam.git_commit = commit)
    return(commit)
  }

  ref <- sub("^ref: ", "", head)
  ref_path <- file.path(root, ".git", ref)
  if (file.exists(ref_path)) {
    commit <- substr(read_first_line(ref_path), 1L, 12L)
    if (!is.na(commit)) options(stbam.git_commit = commit)
    return(commit)
  }

  packed_path <- file.path(root, ".git", "packed-refs")
  if (!file.exists(packed_path)) return(NA_character_)
  packed <- tryCatch(readLines(packed_path, warn = FALSE),
                     error = function(e) character())
  match <- grep(paste0(" ", ref, "$"), packed, value = TRUE)
  if (length(match) == 0L) return(NA_character_)
  commit <- substr(strsplit(match[[1]], " ", fixed = TRUE)[[1]][[1]],
                   1L, 12L)
  options(stbam.git_commit = commit)
  commit
}

#' Build canonical figure metadata for one scenario/receptor/metric
#'
#' Gathers scenario, agronomic, fate, receptor, effects-metric and
#' provenance information from canonical model data into one structure, so
#' plot subtitles, captions, the Shiny "current assumptions" panel and Word
#' export all read from the same source and cannot drift apart.
#'
#' @param row One row of [build_daily_timecourse] output (any `day`; agronomic
#'   and receptor fields are time-invariant) at `diet_fraction == 1`, for one
#'   `scenario_id` x `receptor_id` x `metric_id`.
#' @param effects_metrics Output of [resolve_effects_metrics], used for
#'   provenance fields (`endpoint_description`, `endpoint_value`,
#'   `uncertainty_factor`, `source`) not carried on `row` itself.
#' @param params The `stbam_parameter_set` the row was built from, used to
#'   report override status.
#' @return A named list. See the fields below; every value is read from
#'   canonical model data, never invented.
#' @export
build_figure_metadata <- function(row, effects_metrics, params) {
  if (nrow(row) != 1L) {
    stbam_abort("build_figure_metadata() requires exactly one row; received ",
                nrow(row), ".")
  }
  metric_row <- effects_metrics[
    effects_metrics$metric_id == row$metric_id[[1]],
  ][1, ]
  if (nrow(metric_row) != 1L || is.na(metric_row$metric_id[[1]])) {
    stbam_abort("No effects-metric provenance found for metric_id '",
                row$metric_id[[1]], "'.")
  }

  list(
    # Crop / use.
    crop = row$crop[[1]],
    workbook = row$workbook[[1]],
    scenario_id = row$scenario_id[[1]],
    scenario_label = format_scenario_label(row),
    planting_method_label = row$planting_method_label[[1]],
    rate_level = row$rate_level[[1]],

    # Treatment.
    application_rate = row$application_rate[[1]],
    application_rate_unit = row$application_rate_unit[[1]],
    field_rate_g_ai_per_ha = row$field_rate_g_ai_per_ha[[1]],

    # Agronomic assumptions.
    tkw_g_per_1000 = row$tkw_g_per_1000[[1]],
    seed_mass_g = row$seed_mass_g[[1]],
    seeding_rate_kg_per_ha = row$seeding_rate_kg_per_ha[[1]],
    seeding_rate_bound = row$seeding_rate_bound[[1]],
    seed_mass_bound = row$seed_mass_bound[[1]],
    seeds_per_m2 = row$seeds_per_m2[[1]],
    surface_seed_fraction = row$surface_seed_fraction[[1]],
    initial_surface_seeds_per_m2 = row$initial_surface_seeds_per_m2[[1]],

    # The pool actually driving the maximum-obtainable calculation.
    # SURFACE_SEED_ONLY (all birds): equals initial_surface_seeds_per_m2.
    # SURFACE_PLUS_BURIED (all mammals, ASSUMPTION-020): the FULL sown
    # density, not the surface fraction -- these differ by an order of
    # magnitude or more for drilled/precision-planted crops, and reporting
    # initial_surface_seeds_per_m2 alone would silently understate the pool
    # a mammal figure is actually built on (independent review finding,
    # check 6 of docs/max_obtainable_exposure_review.md).
    accessible_pool_basis = row$accessible_pool_basis[[1]],
    accessible_seeds_per_m2 = row$accessible_seeds_per_m2_t[[1]],

    # Fate / dissipation.
    surface_seed_dt50_days = row$surface_seed_dt50_days[[1]],
    residue_dt50_days = row$residue_dt50_days[[1]],

    # Receptor.
    receptor_id = row$receptor_id[[1]],
    taxon = row$taxon[[1]],
    size_class = row$size_class[[1]],
    receptor_label = format_receptor_label(row$size_class[[1]], row$taxon[[1]],
                                           row$body_weight_g[[1]]),
    body_weight_g = row$body_weight_g[[1]],
    food_intake_g_dw_per_day = row$food_intake_g_dw_per_day[[1]],

    # Maximum search area actually used for this row's taxon/duration class
    # (specification section 10.4), not the manually-toggled msa_m2.
    msa_m2 = row$max_obtainable_msa_m2[[1]],
    msa_term = row$max_obtainable_msa_term[[1]],
    # If msa_m2 itself carries a USER_OVERRIDE at this receptor's scope (or
    # globally), it wins over BOTH the short- and long-term policy lookups
    # and the short/long distinction collapses -- the MAIN-P000209
    # attribution below would then be citing the assessment's policy as the
    # basis for a value that is not the assessment's value (independent
    # review finding A2). Detected here so the footnote can say so rather
    # than silently mis-attribute an overridden value.
    msa_is_overridden = any(
      params$overrides$parameter == "msa_m2" &
        params$overrides$scope %in% c(row$receptor_id[[1]], "global")
    ),
    msa_policy_note = msa_policy_note(row$taxon[[1]],
                                      row$max_obtainable_msa_term[[1]]),

    # Effects metric.
    metric_id = row$metric_id[[1]],
    metric_label = format_metric_label(row$taxon[[1]], row$duration_class[[1]],
                                       row$metric_role[[1]],
                                       row$effects_metric[[1]],
                                       unit = metric_row$unit[[1]]),
    effects_metric_value = row$effects_metric[[1]],
    effects_metric_unit = metric_row$unit[[1]],
    duration_class = row$duration_class[[1]],
    metric_role = row$metric_role[[1]],
    endpoint_description = metric_row$endpoint_description[[1]],
    endpoint_value = metric_row$endpoint_value[[1]],
    uncertainty_factor = metric_row$uncertainty_factor[[1]],
    effects_metric_source = metric_row$source[[1]],

    # RQ / LOC.
    loc = STBAM_DEFAULT_LOC,

    # Provenance.
    parameter_set = row$parameter_set[[1]],
    has_overrides = has_overrides(params),
    override_summary = format_override_summary(params),
    model_version = STBAM_MODEL_VERSION,
    git_commit = read_project_git_commit(),
    generated_at = format(Sys.time(), "%Y-%m-%d %H:%M %Z")
  )
}

#' Render figure metadata as a structured footnote block
#'
#' The same metadata feeds both a `"concise"` version, sized for on-screen
#' Shiny display beside an interactive plot, and a `"full"` version, sized
#' for a figure exported to Word or used in peer-review material, where the
#' figure must be interpretable without Shiny.
#'
#' @param metadata Output of [build_figure_metadata].
#' @param detail `"full"` or `"concise"`.
#' @param width Character width to wrap each footnote line at. Wrapping is
#'   applied per line, preserving the section breaks between lines -- unlike
#'   [wrap_text], which reflows a single paragraph and would destroy them.
#' @param metadata_by_receptor Optional named list of metadata objects, one per
#'   receptor panel. When supplied, every panel's body weight, food requirement
#'   and applicable MSA are reported.
#' @return A single character string, with embedded newlines.
#' @export
format_figure_footnotes <- function(metadata, detail = c("full", "concise"),
                                    width = 100,
                                    metadata_by_receptor = NULL) {
  detail <- match.arg(detail)
  m <- metadata

  # For SURFACE_PLUS_BURIED receptors (all mammals, ASSUMPTION-020) the
  # pool driving the maximum-obtainable calculation is the FULL sown
  # density, not the surface fraction -- reporting only
  # initial_surface_seeds_per_m2 here previously understated the actual
  # pool by an order of magnitude or more for drilled/precision-planted
  # crops (independent review finding, check 6 of
  # docs/max_obtainable_exposure_review.md). Both figures are now stated
  # explicitly whenever they differ.
  pool_clause <- if (identical(m$accessible_pool_basis, "SURFACE_PLUS_BURIED")) {
    sprintf(
      paste(
        "Initial surface seed %s seeds/m2 (%s: %s%% of sown seed on the",
        "surface), but this receptor is modelled with access to the FULL",
        "sown density (%s seeds/m2, ASSUMPTION-020, not surface-restricted)",
        "-- the maximum-obtainable calculation uses %s seeds/m2, not the",
        "surface figure"
      ),
      fmt_sig(m$initial_surface_seeds_per_m2), m$planting_method_label,
      fmt_sig(m$surface_seed_fraction * 100), fmt_sig(m$accessible_seeds_per_m2),
      fmt_sig(m$accessible_seeds_per_m2)
    )
  } else {
    sprintf(
      "Initial surface seed %s seeds/m2 (%s: %s%% of sown seed on the surface)",
      fmt_sig(m$initial_surface_seeds_per_m2), m$planting_method_label,
      fmt_sig(m$surface_seed_fraction * 100)
    )
  }

  agronomy <- sprintf(
    "%s %s (%s g a.i./ha) | TKW %s g/1000 seeds (%s) | Seeding rate %s kg/ha (%s; %s seeds/m2 planted) | %s",
    fmt_sig(m$application_rate), m$application_rate_unit,
    fmt_sig(m$field_rate_g_ai_per_ha), fmt_sig(m$tkw_g_per_1000),
    m$seed_mass_bound, fmt_sig(m$seeding_rate_kg_per_ha),
    m$seeding_rate_bound, fmt_sig(m$seeds_per_m2), pool_clause
  )

  fate <- sprintf(
    "Surface-seed disappearance DT50 = %s d (seeds remaining on the surface) | Residue dissipation DT50 = %s d (a.i. remaining per seed present) | independent first-order processes",
    fmt_sig(m$surface_seed_dt50_days), fmt_sig(m$residue_dt50_days)
  )

  receptor_line <- function(x) sprintf(
    "%s | Body weight %s g | Food requirement %s g dry-weight diet/day | Applicable MSA %s m2 (%s-term%s)",
    x$receptor_label, fmt_sig(x$body_weight_g),
    fmt_sig(x$food_intake_g_dw_per_day), fmt_sig(x$msa_m2), x$msa_term,
    if (isTRUE(x$msa_is_overridden)) ", USER-OVERRIDDEN value" else ""
  )
  receptor <- if (is.null(metadata_by_receptor)) {
    receptor_line(m)
  } else {
    vapply(metadata_by_receptor, receptor_line, character(1), USE.NAMES = FALSE)
  }

  metric <- sprintf(
    "Effects metric: %s | RQ = dose / effects metric; RQ = %s is the level of concern (LOC) used here",
    m$metric_label, fmt_sig(m$loc)
  )

  lines <- c(agronomy, fate, receptor, metric)

  if (detail == "full") {
    if (!is.na(m$endpoint_description) && nzchar(m$endpoint_description)) {
      lines <- c(lines, sprintf(
        "Effects-metric basis: %s (endpoint %s %s; %sx uncertainty factor); source %s",
        m$endpoint_description, fmt_sig(m$endpoint_value), m$effects_metric_unit,
        fmt_sig(m$uncertainty_factor), m$effects_metric_source
      ))
    }
    # Only cite the assessment's MSA policy as the basis for the value
    # actually shown when that value has not itself been overridden -- an
    # overridden msa_m2 wins over both the short- and long-term policy
    # lookups (independent review finding A2), so citing MAIN-P000209 in
    # that case would misattribute a user-supplied number to the source
    # assessment.
    any_msa_overridden <- isTRUE(m$msa_is_overridden) || (
      !is.null(metadata_by_receptor) &&
        any(vapply(metadata_by_receptor, function(x) isTRUE(x$msa_is_overridden),
                   logical(1)))
    )
    lines <- c(lines, if (any_msa_overridden) {
      paste(
        "At least one MSA value shown above is a USER OVERRIDE, not the",
        "assessment default. The short-/long-term distinction from",
        "assessment paragraph MAIN-P000209 does not apply to an overridden",
        "value; it is retained here only for whichever panel is unaffected."
      )
    } else {
      m$msa_policy_note
    })
    lines <- c(lines, paste(
      "100% treated-seed diet: dose/RQ if the receptor obtained its full",
      "daily dietary requirement as treated seed, regardless of whether",
      "that much treated seed is physically present."
    ))
    lines <- c(lines, paste(
      "Maximum obtainable within MSA: the maximum dose/RQ actually",
      "achievable, capped at the lesser of the receptor's daily food",
      "requirement and the treated seed available within the applicable",
      "MSA. A refinement/diagnostic; it does not replace or silently",
      "modify the conditional calculation above."
    ))
  }

  if (isTRUE(m$has_overrides)) {
    lines <- c(lines, sprintf(
      "SCENARIO CONTAINS USER OVERRIDES (not the assessment default): %s",
      m$override_summary
    ))
  } else {
    lines <- c(lines, "Assessment baseline. No overrides applied.")
  }

  if (detail == "full") {
    lines <- c(lines, sprintf(
      "Scenario ID: %s | Parameter set: %s | Model version %s | Git commit %s | Generated %s",
      m$scenario_id, m$parameter_set, m$model_version,
      ifelse(is.na(m$git_commit), "unavailable", m$git_commit), m$generated_at
    ))
  }

  wrapped <- vapply(lines, wrap_text, character(1), width = width,
                    USE.NAMES = FALSE)
  paste(wrapped, collapse = "\n")
}
