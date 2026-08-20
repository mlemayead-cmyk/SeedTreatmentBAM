# Canonical dataset 2: daily_timecourse.
#
# One row per scenario x receptor x effects metric x dietary fraction x day.
# Specification section 11.2.

#' Build the daily time course
#'
#' @param params An `stbam_parameter_set`.
#' @param scenario_inputs Output of [build_scenario_inputs].
#' @param receptors Output of [resolve_receptors]; defaults to all receptors.
#' @param effects_metrics Output of [resolve_effects_metrics]; defaults to the
#'   screening metrics.
#' @param diet_fractions Dietary fractions to evaluate.
#' @param days Days since sowing to evaluate.
#' @return A tibble of daily results.
#' @export
build_daily_timecourse <- function(params, scenario_inputs, receptors = NULL,
                                   effects_metrics = NULL,
                                   diet_fractions = STBAM_DIET_FRACTIONS,
                                   days = 0:60) {
  check_numeric(days, "days", min = 0)
  if (is.null(receptors)) receptors <- resolve_receptors(params)
  if (is.null(effects_metrics)) effects_metrics <- resolve_effects_metrics(params)

  dissipation <- resolve_dissipation(params)
  residue_dt50 <- dissipation$residue$value
  surface_dt50 <- dissipation$surface_seed$value

  grid <- build_exposure_grid(scenario_inputs, receptors, effects_metrics,
                              diet_fractions)

  expanded <- dplyr::cross_join(grid, tibble::tibble(day = as.numeric(days)))

  # Surface seed and residue decline are independent processes with independent
  # half-lives (specification section 7).
  expanded$surface_seeds_per_m2 <- surface_seed_over_time(
    expanded$initial_surface_seeds_per_m2, expanded$day, surface_dt50
  )
  expanded$accessible_seeds_per_m2_t <- stbam_ifelse(
    expanded$surface_seed_only,
    expanded$surface_seeds_per_m2,
    expanded$seeds_per_m2 * first_order_remaining(expanded$day, surface_dt50)
  )
  expanded$ai_per_seed_mg <- ai_per_seed_over_time(
    expanded$dose_per_seed_mg, expanded$day, residue_dt50
  )
  expanded$surface_ai_mg_per_m2 <-
    expanded$surface_seeds_per_m2 * expanded$ai_per_seed_mg

  # Calculated regulatory exposure. Not capped at the feasible dietary
  # fraction (specification section 10.3).
  expanded$dose_mg_kg_bw_day <- daily_dose_over_time(
    expanded$initial_dose_mg_kg_bw_day, expanded$day, residue_dt50
  )
  expanded$rq <- risk_quotient(expanded$dose_mg_kg_bw_day,
                               expanded$effects_metric)
  expanded$above_loc <- expanded$rq >= 1

  # Exposure-feasibility analysis, reported separately.
  expanded$available_seeds_within_msa <- available_seed_within_msa(
    expanded$accessible_seeds_per_m2_t, expanded$msa_m2
  )
  expanded$required_search_area_m2 <- required_search_area(
    expanded$seeds_required_per_day, expanded$accessible_seeds_per_m2_t
  )
  expanded$max_feasible_diet_fraction <- maximum_feasible_diet_fraction(
    expanded$accessible_seeds_per_m2_t, expanded$msa_m2,
    expanded$food_intake_g_dw_per_day, expanded$seed_mass_g
  )
  expanded$diet_fraction_is_feasible <- diet_fraction_is_feasible(
    expanded$diet_fraction, expanded$max_feasible_diet_fraction
  )

  # Provided for sensitivity work only. Never substituted for the regulatory
  # dose above.
  expanded$dose_capped_at_feasible_mg_kg_bw_day <- estimated_daily_exposure(
    expanded$concentration_mg_per_kg_seed, expanded$food_intake_g_dw_per_day,
    expanded$body_weight_g,
    pmin(expanded$diet_fraction, pmin(expanded$max_feasible_diet_fraction, 1))
  ) * first_order_remaining(expanded$day, residue_dt50)

  expanded$residue_dt50_days <- residue_dt50
  expanded$surface_seed_dt50_days <- surface_dt50
  expanded$provenance_class <- "CALCULATED"

  dplyr::select(
    expanded,
    "scenario_id", "workbook", "crop", "rate_level", "application_rate",
    "application_rate_unit", "planting_method", "planting_method_label",
    "seeding_rate_bound", "seed_mass_bound",
    "receptor_id", "taxon", "size_class", "body_weight_g",
    "food_intake_g_dw_per_day", "msa_term", "msa_m2",
    "metric_id", "duration_class", "metric_role", "effects_metric",
    "diet_fraction", "day",
    "tkw_g_per_1000", "seed_mass_g", "seeds_per_ha", "seeding_rate_kg_per_ha",
    "concentration_mg_per_kg_seed", "dose_per_seed_mg",
    "field_rate_g_ai_per_ha", "surface_seed_fraction",
    "initial_surface_seeds_per_m2", "surface_seeds_per_m2",
    "accessible_seeds_per_m2_t", "accessible_pool_basis",
    "ai_per_seed_mg", "surface_ai_mg_per_m2",
    "seeds_required_full_diet", "seeds_required_per_day",
    "ede_full_diet", "initial_dose_mg_kg_bw_day", "dose_mg_kg_bw_day",
    "rq", "above_loc",
    "available_seeds_within_msa", "required_search_area_m2",
    "max_feasible_diet_fraction", "diet_fraction_is_feasible",
    "dose_capped_at_feasible_mg_kg_bw_day",
    "residue_dt50_days", "surface_seed_dt50_days",
    "parameter_set", "provenance_class"
  )
}
