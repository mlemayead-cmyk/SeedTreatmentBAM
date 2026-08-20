# Canonical dataset 4: table162_support.
#
# Joins the calculated quantitative backbone to the review workspace's Table 162
# decision matrix and consideration register.
#
# THE SOFTWARE DOES NOT MAKE THE DECISION. Fields carrying peer-review
# consensus are created empty and are never written to by any code path.

#' Map a source workbook to the crop family used by the decision matrix
#' @noRd
STBAM_WORKBOOK_TO_CROP_FAMILY <- c(
  small_cereals = "Small Cereals",
  small_cereals_msa = "Small Cereals",
  canola = "Canola/Mustard",
  legumes_deep = "Legumes",
  legumes_shallow = "Legumes",
  cucurbits = "Cucurbits"
)

#' Map model planting methods to decision-matrix planting-method labels
#'
#' The register uses several spellings for the same method; all are accepted.
#' @noRd
STBAM_METHOD_TO_REGISTER <- list(
  broadcast = "Broadcast",
  drill_spring = c("Spring drill", "Standard drill (spring)", "Standard drilling"),
  drill_fall = "Fall drill",
  precision = "Precision"
)

#' Fields that only a human may complete
#' @export
STBAM_HUMAN_ONLY_FIELDS <- c("peer_review_consensus", "consensus_rationale")

#' Load the Table 162 decision matrix and consideration register
#'
#' @param params An `stbam_parameter_set`.
#' @return A list with `decisions` and `considerations`.
#' @export
load_table162_registers <- function(params) {
  list(
    decisions = read_reference("table162_decision_matrix.csv"),
    considerations = read_reference("table162_considerations.csv")
  )
}

#' @noRd
parse_register_rate <- function(text) {
  # Register rates look like "300 mg a.i./kg seed" or "0.045 mg a.i./seed".
  # Compound entries such as "4000, 4035 mg a.i./kg seed" take the first value.
  value <- suppressWarnings(as.numeric(
    sub("^\\s*([0-9.]+).*$", "\\1", text)
  ))
  unit <- ifelse(grepl("kg seed", text, fixed = TRUE), "mg a.i./kg seed",
                 ifelse(grepl("/seed", text, fixed = TRUE), "mg a.i./seed",
                        NA_character_))
  list(value = value, unit = unit)
}

#' Build the Table 162 quantitative backbone
#'
#' One row per crop family x planting method x taxon x receptor size x effect
#' window, summarising the calculated results that bear on the decision.
#'
#' @param scenario_summary Output of [build_scenario_summary].
#' @return A tibble of quantitative decision support.
#' @export
build_table162_backbone <- function(scenario_summary) {
  data <- scenario_summary
  data$crop_family <- unname(STBAM_WORKBOOK_TO_CROP_FAMILY[data$workbook])
  data$receptor_size <- tools::toTitleCase(data$size_class)
  data$taxon_label <- tools::toTitleCase(data$taxon)
  data$effect_window <- tools::toTitleCase(data$duration_class)

  dplyr::summarise(
    dplyr::group_by(
      data, .data$crop_family, .data$workbook, .data$crop, .data$rate_level,
      .data$application_rate, .data$application_rate_unit,
      .data$planting_method, .data$planting_method_label,
      .data$taxon_label, .data$receptor_size, .data$effect_window,
      .data$metric_id, .data$metric_role, .data$effects_metric
    ),
    # Magnitude of exceedance.
    screening_rq_max = max(.data$screening_rq),
    refined_rq_max_at_100pct = max(
      .data$initial_rq[.data$diet_fraction == 1], na.rm = TRUE
    ),
    peak_rq_max = max(.data$peak_rq),
    # Duration.
    days_above_loc_max = max(.data$days_above_loc),
    days_above_loc_at_100pct = max(
      .data$days_above_loc[.data$diet_fraction == 1], na.rm = TRUE
    ),
    threshold_diet_pct_min = min(.data$threshold_diet_fraction_pct),
    # Seed availability.
    initial_surface_seeds_per_m2_min = min(.data$initial_surface_seeds_per_m2),
    initial_surface_seeds_per_m2_max = max(.data$initial_surface_seeds_per_m2),
    field_rate_g_ai_per_ha_max = max(.data$field_rate_g_ai_per_ha),
    # Exposure feasibility.
    max_feasible_diet_pct_max = max(.data$initial_max_feasible_diet_fraction) * 100,
    days_at_full_diet_available_max = max(.data$days_at_full_diet_available),
    required_search_area_m2_min = min(.data$initial_required_search_area_m2),
    msa_m2 = max(.data$msa_m2),
    highest_feasible_diet_fraction = max(
      c(0, .data$diet_fraction[.data$diet_fraction_is_feasible_at_sowing])
    ),
    n_scenarios = dplyr::n(),
    .groups = "drop"
  )
}

#' Build the Table 162 decision-support dataset
#'
#' Joins the calculated backbone to the decision matrix and the consideration
#' register, keeping quantitative results, source evidence and human judgement
#' in separate, clearly labelled fields.
#'
#' @param params An `stbam_parameter_set`.
#' @param scenario_summary Output of [build_scenario_summary].
#' @param metric_role Which effects-metric role to use for the backbone.
#' @return A tibble of Table 162 decision support.
#' @export
build_table162_support <- function(params, scenario_summary,
                                   metric_role = "SCREENING") {
  registers <- load_table162_registers(params)
  decisions <- registers$decisions
  considerations <- registers$considerations

  backbone <- build_table162_backbone(scenario_summary)
  backbone <- backbone[backbone$metric_role %in% metric_role, ]

  parsed <- parse_register_rate(decisions$application_rate)
  decisions$rate_value <- parsed$value
  decisions$rate_unit <- parsed$unit

  method_map <- do.call(rbind, lapply(names(STBAM_METHOD_TO_REGISTER),
                                      function(model_method) {
    data.frame(
      planting_method = model_method,
      register_method = STBAM_METHOD_TO_REGISTER[[model_method]],
      stringsAsFactors = FALSE
    )
  }))
  backbone <- dplyr::left_join(backbone, method_map, by = "planting_method",
                               relationship = "many-to-many")

  joined <- dplyr::left_join(
    decisions,
    backbone,
    by = c("crop_family" = "crop_family",
           "planting_method" = "register_method",
           "taxon" = "taxon_label",
           "receptor_size" = "receptor_size",
           "effect_window" = "effect_window",
           "rate_value" = "application_rate",
           "rate_unit" = "application_rate_unit"),
    relationship = "many-to-many",
    suffix = c("", "_model")
  )

  # Summarise the consideration register into direction-separated evidence.
  considerations$decision_list <- strsplit(
    considerations$table162_decision_ids, "\\s*;\\s*"
  )
  exploded <- tibble::tibble(
    decision_id = unlist(considerations$decision_list),
    consideration_id = rep(considerations$consideration_id,
                           lengths(considerations$decision_list)),
    theme = rep(considerations$theme, lengths(considerations$decision_list)),
    direction = rep(considerations$direction,
                    lengths(considerations$decision_list)),
    text = rep(considerations$concise_consideration,
               lengths(considerations$decision_list)),
    evidence_type = rep(considerations$evidence_type,
                        lengths(considerations$decision_list)),
    uncertainty = rep(considerations$uncertainty_qualification,
                      lengths(considerations$decision_list)),
    scenario_applicability = rep(considerations$scenario_applicability,
                                 lengths(considerations$decision_list)),
    interpretation_flag = rep(considerations$evidence_interpretation_or_judgment,
                              lengths(considerations$decision_list))
  )

  collapse_direction <- function(df, wanted) {
    hits <- df$text[df$direction %in% wanted]
    if (length(hits) == 0L) NA_character_ else paste(hits, collapse = " | ")
  }

  evidence <- dplyr::summarise(
    dplyr::group_by(exploded, .data$decision_id),
    factors_increasing_concern = collapse_direction(
      dplyr::pick(dplyr::everything()), "INCREASES_CONCERN"
    ),
    factors_decreasing_concern = collapse_direction(
      dplyr::pick(dplyr::everything()), "DECREASES_CONCERN"
    ),
    contextual_evidence = collapse_direction(
      dplyr::pick(dplyr::everything()),
      setdiff(unique(.data$direction), c("INCREASES_CONCERN",
                                         "DECREASES_CONCERN"))
    ),
    important_uncertainty = paste(unique(stats::na.omit(.data$uncertainty)),
                                  collapse = " | "),
    scenario_applicability_notes = paste(
      unique(stats::na.omit(.data$scenario_applicability)), collapse = " | "
    ),
    consideration_count = dplyr::n(),
    .groups = "drop"
  )

  out <- dplyr::left_join(joined, evidence, by = "decision_id")

  result <- tibble::tibble(
    decision_id = out$decision_id,
    table_id = out$table_id,
    crop_family = out$crop_family,
    crop_use = out$crop_use,
    application_rate = out$application_rate,
    planting_method = out$planting_method,
    taxon = out$taxon,
    receptor_size = out$receptor_size,
    effect_window = out$effect_window,

    # PEER_REVIEW_DECISION: current recorded position, read only.
    current_table162_position = out$current_position,

    # CALCULATED: quantitative backbone.
    model_crop = out$crop,
    model_metric_id = out$metric_id,
    model_effects_metric = out$effects_metric,
    screening_rq_max = out$screening_rq_max,
    refined_rq_at_full_diet = out$refined_rq_max_at_100pct,
    peak_rq_max = out$peak_rq_max,
    days_above_loc_max = out$days_above_loc_max,
    days_above_loc_at_full_diet = out$days_above_loc_at_100pct,
    threshold_diet_pct = out$threshold_diet_pct_min,
    surface_seeds_per_m2_min = out$initial_surface_seeds_per_m2_min,
    surface_seeds_per_m2_max = out$initial_surface_seeds_per_m2_max,
    field_rate_g_ai_per_ha_max = out$field_rate_g_ai_per_ha_max,
    max_feasible_diet_pct = out$max_feasible_diet_pct_max,
    days_at_full_diet_available = out$days_at_full_diet_available_max,
    required_search_area_m2_min = out$required_search_area_m2_min,
    msa_m2 = out$msa_m2,
    highest_feasible_diet_fraction = out$highest_feasible_diet_fraction,
    quantitative_backbone_available = !is.na(out$peak_rq_max),

    # SOURCE_EVIDENCE and REVIEWER_INTERPRETATION, kept separate.
    factors_increasing_concern = out$factors_increasing_concern,
    factors_decreasing_concern = out$factors_decreasing_concern,
    contextual_evidence = out$contextual_evidence,
    important_uncertainty = out$important_uncertainty,
    scenario_applicability = out$scenario_applicability_notes,
    current_narrative_reasoning = out$apparent_primary_rationale,
    evidence_to_conclusion_consistency = out$evidence_to_conclusion_consistency,
    peer_review_question_ids = out$peer_review_question_ids,
    traceability_status = out$traceability_status,

    # Human-only. Created empty and never populated by any code path.
    peer_review_consensus = NA_character_,
    consensus_rationale = NA_character_
  )

  attr(result, "human_only_fields") <- STBAM_HUMAN_ONLY_FIELDS
  result
}

#' Report which decision rows the model could and could not quantify
#'
#' Crop families with no supplied calculation workbook cannot have a
#' quantitative backbone. Reporting that explicitly is required; silently
#' dropping those rows is not acceptable.
#'
#' Published Table 162 rows are grouped across crops, so one decision row can
#' match several model crops. Coverage is therefore counted over DISTINCT
#' decision ids, not over rows of the support table.
#'
#' @param table162_support Output of [build_table162_support].
#' @return A tibble of coverage by crop family.
#' @export
table162_coverage <- function(table162_support) {
  per_decision <- dplyr::summarise(
    dplyr::group_by(table162_support, .data$crop_family, .data$decision_id),
    has_backbone = any(.data$quantitative_backbone_available, na.rm = TRUE),
    model_crops = dplyr::n_distinct(
      .data$model_crop[!is.na(.data$model_crop)]
    ),
    .groups = "drop"
  )
  dplyr::arrange(
    dplyr::summarise(
      dplyr::group_by(per_decision, .data$crop_family),
      decision_rows = dplyr::n_distinct(.data$decision_id),
      with_quantitative_backbone = sum(.data$has_backbone),
      without_quantitative_backbone = sum(!.data$has_backbone),
      coverage_pct = round(100 * sum(.data$has_backbone) /
                             dplyr::n_distinct(.data$decision_id), 1),
      mean_model_crops_per_decision = round(mean(.data$model_crops), 1),
      .groups = "drop"
    ),
    dplyr::desc(.data$decision_rows)
  )
}

#' Verify that no human-only field has been populated by the software
#'
#' Called by the test suite and before any export.
#'
#' @param table162_support Output of [build_table162_support].
#' @return `TRUE`, invisibly. Errors if a human-only field is populated.
#' @export
assert_human_fields_empty <- function(table162_support) {
  for (field in STBAM_HUMAN_ONLY_FIELDS) {
    if (!field %in% names(table162_support)) next
    populated <- sum(!is.na(table162_support[[field]]))
    if (populated > 0L) {
      stbam_abort(
        "The human-only field `", field, "` has ", populated,
        " populated value(s). Peer-review consensus must never be written by ",
        "the software."
      )
    }
  }
  invisible(TRUE)
}
