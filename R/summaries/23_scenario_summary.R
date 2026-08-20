# Canonical dataset 3: scenario_summary.
#
# One row per scenario x receptor x effects metric x dietary fraction.
# Specification section 11.3.
#
# Every summary quantity here has a closed form, so this table is computed
# directly rather than by scanning a daily time course. That keeps a full
# crop x rate x method x receptor x metric x diet build fast, and it removes
# any dependence on the resolution of the day grid.

#' Build the scenario summary
#'
#' @param params An `stbam_parameter_set`.
#' @param scenario_inputs Output of [build_scenario_inputs].
#' @param receptors Output of [resolve_receptors]; defaults to all receptors.
#' @param effects_metrics Output of [resolve_effects_metrics]; defaults to the
#'   screening metrics.
#' @param diet_fractions Dietary fractions to evaluate.
#' @return A tibble of scenario summaries.
#' @export
build_scenario_summary <- function(params, scenario_inputs, receptors = NULL,
                                   effects_metrics = NULL,
                                   diet_fractions = STBAM_DIET_FRACTIONS) {
  if (is.null(receptors)) receptors <- resolve_receptors(params)
  if (is.null(effects_metrics)) effects_metrics <- resolve_effects_metrics(params)

  dissipation <- resolve_dissipation(params)
  residue_dt50 <- dissipation$residue$value
  surface_dt50 <- dissipation$surface_seed$value

  g <- build_exposure_grid(scenario_inputs, receptors, effects_metrics,
                           diet_fractions)

  # Screening RQ: maximum rate, 100 percent treated-seed diet
  # (ASSUMPTION-001, ASSUMPTION-002).
  g$screening_rq <- risk_quotient(g$ede_full_diet, g$effects_metric)
  g$initial_rq <- risk_quotient(g$initial_dose_mg_kg_bw_day, g$effects_metric)

  # Dose declines monotonically under first-order dissipation, so the peak
  # occurs at sowing.
  g$peak_rq <- g$initial_rq
  g$peak_rq_day <- 0

  g$days_above_loc <- duration_above_effect_metric(
    g$initial_dose_mg_kg_bw_day, g$effects_metric, residue_dt50
  )
  g$day_below_loc <- stbam_ifelse(g$days_above_loc > 0, g$days_above_loc,
                                  NA_real_)
  g$threshold_diet_fraction_pct <- threshold_diet_fraction_pct(
    g$ede_full_diet, g$effects_metric
  )
  g$seeds_to_metric <- seeds_to_effect_metric(
    g$effects_metric, g$body_weight_g, g$dose_per_seed_mg
  )

  # Exposure feasibility at sowing.
  g$initial_available_seeds_within_msa <- available_seed_within_msa(
    g$accessible_seeds_per_m2, g$msa_m2
  )
  g$initial_required_search_area_m2 <- required_search_area(
    g$seeds_required_per_day, g$accessible_seeds_per_m2
  )
  g$initial_max_feasible_diet_fraction <- maximum_feasible_diet_fraction(
    g$accessible_seeds_per_m2, g$msa_m2, g$food_intake_g_dw_per_day,
    g$seed_mass_g
  )
  g$diet_fraction_is_feasible_at_sowing <- diet_fraction_is_feasible(
    g$diet_fraction, g$initial_max_feasible_diet_fraction
  )
  g$area_to_reach_metric_m2 <- required_search_area(
    g$seeds_to_metric, g$accessible_seeds_per_m2
  )

  # Days for which a given dietary fraction remains obtainable, using the
  # surface-seed half-life.
  g$days_at_full_diet_available <- days_diet_fraction_feasible(
    g$initial_max_feasible_diet_fraction, 1, surface_dt50
  )
  g$day_100pct_diet_infeasible <- g$days_at_full_diet_available
  g$day_50pct_diet_infeasible <- days_diet_fraction_feasible(
    g$initial_max_feasible_diet_fraction, 0.50, surface_dt50
  )
  g$day_25pct_diet_infeasible <- days_diet_fraction_feasible(
    g$initial_max_feasible_diet_fraction, 0.25, surface_dt50
  )
  g$days_assumed_diet_feasible <- days_diet_fraction_feasible(
    g$initial_max_feasible_diet_fraction, g$diet_fraction, surface_dt50
  )

  g$residue_dt50_days <- residue_dt50
  g$surface_seed_dt50_days <- surface_dt50
  g$provenance_class <- "DERIVED"

  dplyr::select(
    g,
    "scenario_id", "workbook", "crop", "rate_level", "application_rate",
    "application_rate_unit", "planting_method", "planting_method_label",
    "seeding_rate_bound", "seed_mass_bound", "seeding_basis",
    "receptor_id", "taxon", "size_class", "body_weight_g",
    "food_intake_g_dw_per_day", "msa_term", "msa_m2",
    "metric_id", "duration_class", "metric_role", "effects_metric",
    "endpoint_description", "diet_fraction",
    "tkw_g_per_1000", "seed_mass_g", "seeds_per_ha", "seeds_per_m2",
    "seeding_rate_kg_per_ha", "concentration_mg_per_kg_seed",
    "dose_per_seed_mg", "field_rate_g_ai_per_ha", "surface_seed_fraction",
    "initial_surface_seeds_per_m2", "area_per_surface_seed_m2",
    "accessible_seeds_per_m2", "accessible_pool_basis",
    "seeds_required_full_diet", "seeds_required_per_day",
    "ede_full_diet", "initial_dose_mg_kg_bw_day",
    "screening_rq", "initial_rq", "peak_rq", "peak_rq_day",
    "days_above_loc", "day_below_loc", "threshold_diet_fraction_pct",
    "seeds_to_metric", "area_to_reach_metric_m2",
    "initial_available_seeds_within_msa", "initial_required_search_area_m2",
    "initial_max_feasible_diet_fraction", "diet_fraction_is_feasible_at_sowing",
    "days_at_full_diet_available", "day_100pct_diet_infeasible",
    "day_50pct_diet_infeasible", "day_25pct_diet_infeasible",
    "days_assumed_diet_feasible",
    "residue_dt50_days", "surface_seed_dt50_days",
    "tkw_status", "rate_status", "seeding_status", "surface_fraction_status",
    "body_weight_status", "food_intake_status", "msa_status",
    "effects_metric_status", "parameter_set", "provenance_class"
  )
}

#' Collapse a summary to published-style ranges across the agronomic bounds
#'
#' The source Word tables group crops and report ranges across the seeding-rate
#' and seed-mass bounds. This reproduces that presentation from the canonical
#' grid rather than hard-coding it, so the range and the combination that
#' produced each end of it stay connected.
#'
#' @param scenario_summary Output of [build_scenario_summary].
#' @param group_by Columns defining a published table row.
#' @return A tibble of ranges.
#' @export
summarise_across_bounds <- function(
    scenario_summary,
    group_by = c("crop", "rate_level", "planting_method", "receptor_id",
                 "metric_id", "diet_fraction")) {
  dplyr::summarise(
    dplyr::group_by(scenario_summary, dplyr::across(dplyr::all_of(group_by))),
    n_bound_combinations = dplyr::n(),
    seeds_per_m2_min = min(.data$seeds_per_m2),
    seeds_per_m2_max = max(.data$seeds_per_m2),
    initial_surface_seeds_per_m2_min = min(.data$initial_surface_seeds_per_m2),
    initial_surface_seeds_per_m2_max = max(.data$initial_surface_seeds_per_m2),
    field_rate_g_ai_per_ha_min = min(.data$field_rate_g_ai_per_ha),
    field_rate_g_ai_per_ha_max = max(.data$field_rate_g_ai_per_ha),
    dose_per_seed_mg_min = min(.data$dose_per_seed_mg),
    dose_per_seed_mg_max = max(.data$dose_per_seed_mg),
    seeds_required_per_day_min = min(.data$seeds_required_per_day),
    seeds_required_per_day_max = max(.data$seeds_required_per_day),
    dose_mg_kg_bw_day_min = min(.data$initial_dose_mg_kg_bw_day),
    dose_mg_kg_bw_day_max = max(.data$initial_dose_mg_kg_bw_day),
    rq_min = min(.data$initial_rq),
    rq_max = max(.data$initial_rq),
    days_above_loc_min = min(.data$days_above_loc),
    days_above_loc_max = max(.data$days_above_loc),
    required_search_area_m2_min = min(.data$initial_required_search_area_m2),
    required_search_area_m2_max = max(.data$initial_required_search_area_m2),
    max_feasible_diet_fraction_min = min(.data$initial_max_feasible_diet_fraction),
    max_feasible_diet_fraction_max = max(.data$initial_max_feasible_diet_fraction),
    days_at_full_diet_available_min = min(.data$days_at_full_diet_available),
    days_at_full_diet_available_max = max(.data$days_at_full_diet_available),
    .groups = "drop"
  )
}
