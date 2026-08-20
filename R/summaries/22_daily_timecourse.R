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
  expanded$above_loc <- expanded$rq >= STBAM_DEFAULT_LOC

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

  # --- Maximum obtainable exposure -----------------------------------------
  #
  # A second, assessment-policy-grounded MSA feasibility layer, distinct from
  # the manually-toggled `msa_m2`/`available_seeds_within_msa`/
  # `max_feasible_diet_fraction` columns above (which remain exactly as they
  # were, driven by whatever `msa_term` the caller passed to
  # resolve_receptors()). This layer instead resolves the search area the
  # source assessment itself actually uses for each row's taxon and duration
  # class (specification section 10.4; resolve_msa_term_for_metric()):
  # always short-term for birds, short-term for mammalian acute and
  # long-term for mammalian chronic/refined characterization. It answers
  # "given the source assessment's own MSA policy, how much treated seed
  # could this receptor actually obtain, capped at its own food
  # requirement" -- never assuming every available seed is eaten if that
  # would exceed the assumed dietary requirement.
  receptor_ids <- unique(receptors$receptor_id)
  receptors_short <- resolve_receptors(params, receptor_ids, msa_term = "short")
  receptors_long <- resolve_receptors(params, receptor_ids, msa_term = "long")
  short_lookup <- stats::setNames(receptors_short$msa_m2,
                                  receptors_short$receptor_id)
  long_lookup <- stats::setNames(receptors_long$msa_m2,
                                 receptors_long$receptor_id)

  expanded$max_obtainable_msa_term <- resolve_msa_term_for_metric(
    expanded$taxon, expanded$duration_class
  )
  expanded$max_obtainable_msa_m2 <- stbam_ifelse(
    expanded$max_obtainable_msa_term == "short",
    unname(short_lookup[expanded$receptor_id]),
    unname(long_lookup[expanded$receptor_id])
  )
  expanded$max_obtainable_seeds_within_msa <- available_seed_within_msa(
    expanded$accessible_seeds_per_m2_t, expanded$max_obtainable_msa_m2
  )
  expanded$max_obtainable_diet_fraction <- maximum_feasible_diet_fraction(
    expanded$accessible_seeds_per_m2_t, expanded$max_obtainable_msa_m2,
    expanded$food_intake_g_dw_per_day, expanded$seed_mass_g
  )
  expanded$diet_fraction_is_obtainable <- diet_fraction_is_feasible(
    expanded$diet_fraction, expanded$max_obtainable_diet_fraction
  )
  expanded$max_obtainable_seeds_per_day <- max_obtainable_seeds_per_day(
    expanded$seeds_required_per_day, expanded$max_obtainable_seeds_within_msa
  )
  # Reuses the same validated per-seed dose function as the conditional
  # (100%-of-assumed-diet) dose above; only the seed count differs.
  expanded$max_obtainable_dose_mg_kg_bw_day <- daily_ai_intake_dose(
    expanded$max_obtainable_seeds_per_day, expanded$ai_per_seed_mg,
    expanded$body_weight_g
  )
  expanded$max_obtainable_rq <- risk_quotient(
    expanded$max_obtainable_dose_mg_kg_bw_day, expanded$effects_metric
  )
  expanded$above_loc_max_obtainable <-
    expanded$max_obtainable_rq >= STBAM_DEFAULT_LOC

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
    "tkw_g_per_1000", "seed_mass_g", "seeds_per_ha", "seeds_per_m2",
    "seeding_rate_kg_per_ha",
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
    "max_obtainable_msa_term", "max_obtainable_msa_m2",
    "max_obtainable_seeds_within_msa", "max_obtainable_diet_fraction",
    "diet_fraction_is_obtainable", "max_obtainable_seeds_per_day",
    "max_obtainable_dose_mg_kg_bw_day", "max_obtainable_rq",
    "above_loc_max_obtainable",
    "residue_dt50_days", "surface_seed_dt50_days",
    "parameter_set", "provenance_class"
  )
}
