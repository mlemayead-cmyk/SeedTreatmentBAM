# Resolving receptor and dissipation parameters, and the exposure grid.
#
# Shared by the daily timecourse and the closed-form scenario summary.

#' Standard dietary fractions used by the assessment tables
#' @export
STBAM_DIET_FRACTIONS <- c(1.00, 0.50, 0.25, 0.10, 0.05, 0.01)

#' Resolve receptor parameters with any overrides applied
#'
#' @param params An `stbam_parameter_set`.
#' @param receptors Optional character vector of receptor ids.
#' @param msa_term Which maximum search area to use: `"short"` or `"long"`.
#' @return A tibble of effective receptor parameters.
#' @export
resolve_receptors <- function(params, receptors = NULL, msa_term = "short") {
  check_choice(msa_term, "msa_term", c("short", "long"))
  table <- params$baseline$receptors
  if (!is.null(receptors)) {
    check_choice(receptors, "receptors", table$receptor_id)
    table <- table[table$receptor_id %in% receptors, ]
  }

  out <- vector("list", nrow(table))
  for (i in seq_len(nrow(table))) {
    row <- table[i, ]
    bw <- effective_value(params, "body_weight_g", scope = row$receptor_id,
                          default = row$body_weight_g)
    # A body-weight override must propagate through the allometric regression,
    # otherwise food intake would silently remain at the baseline weight.
    default_fir <- if (identical(bw$status, "ASSESSMENT_DEFAULT")) {
      row$food_intake_g_dw_per_day
    } else {
      food_requirement(bw$value, row$fir_coefficient_a, row$fir_exponent_b)
    }
    fir <- effective_value(params, "food_intake_g_dw_per_day",
                           scope = row$receptor_id, default = default_fir)
    baseline_msa <- if (msa_term == "short") {
      row$msa_short_term_m2
    } else {
      row$msa_long_term_m2
    }
    msa <- effective_value(params, "msa_m2", scope = row$receptor_id,
                           default = baseline_msa)

    out[[i]] <- tibble::tibble(
      receptor_id = row$receptor_id,
      taxon = row$taxon,
      size_class = row$size_class,
      body_weight_g = bw$value,
      fir_regression_name = row$fir_regression_name,
      food_intake_g_dw_per_day = fir$value,
      msa_term = msa_term,
      msa_m2 = msa$value,
      surface_seed_only = row$surface_seed_only,
      body_weight_status = bw$status,
      food_intake_status = fir$status,
      msa_status = msa$status
    )
  }
  dplyr::bind_rows(out)
}

#' Resolve the two dissipation half-lives with any overrides applied
#'
#' @param params An `stbam_parameter_set`.
#' @return A list with `residue_dt50_days` and `surface_seed_dt50_days`, each a
#'   list of `value` and `status`.
#' @export
resolve_dissipation <- function(params) {
  list(
    residue = effective_value(
      params, "residue_dt50_days", scope = "global",
      default = dissipation_default(params$baseline, "residue_dt50_days")
    ),
    surface_seed = effective_value(
      params, "surface_seed_dt50_days", scope = "global",
      default = dissipation_default(params$baseline, "surface_seed_dt50_days")
    )
  )
}

#' Resolve effects metrics with any overrides applied
#'
#' @param params An `stbam_parameter_set`.
#' @param metric_roles Roles to include, e.g. `"SCREENING"`.
#' @param taxa Optional taxon filter.
#' @return A tibble of effective effects metrics.
#' @export
resolve_effects_metrics <- function(params, metric_roles = "SCREENING",
                                    taxa = NULL) {
  table <- params$baseline$effects_metrics
  table <- table[table$metric_role %in% metric_roles, ]
  if (!is.null(taxa)) {
    table <- table[table$taxon %in% taxa, ]
  }
  if (nrow(table) == 0L) {
    stbam_abort("No effects metrics matched roles ",
                paste(metric_roles, collapse = ", "),
                ". Available roles: ",
                paste(unique(params$baseline$effects_metrics$metric_role),
                      collapse = ", "))
  }
  values <- vapply(seq_len(nrow(table)), function(i) {
    effective_value(params, "effects_metric", scope = table$metric_id[[i]],
                    default = table$effects_metric[[i]])$value
  }, numeric(1))
  statuses <- vapply(seq_len(nrow(table)), function(i) {
    effective_value(params, "effects_metric", scope = table$metric_id[[i]],
                    default = table$effects_metric[[i]])$status
  }, character(1))
  table$effects_metric <- values
  table$effects_metric_status <- statuses
  table
}

#' Build the crossed exposure grid
#'
#' Joins scenario inputs, receptors, effects metrics and dietary fractions.
#' Metrics are matched to receptors by taxon so a bird is never assessed
#' against a mammalian metric.
#'
#' @param scenario_inputs Output of [build_scenario_inputs].
#' @param receptors Output of [resolve_receptors].
#' @param effects_metrics Output of [resolve_effects_metrics].
#' @param diet_fractions Numeric vector of dietary fractions, 0-1.
#' @return A tibble, one row per scenario x receptor x metric x diet fraction.
#' @export
build_exposure_grid <- function(scenario_inputs, receptors, effects_metrics,
                                diet_fractions = STBAM_DIET_FRACTIONS) {
  check_numeric(diet_fractions, "diet_fractions", min = 0, max = 1)

  grid <- dplyr::cross_join(scenario_inputs, receptors)
  grid <- dplyr::inner_join(
    grid,
    dplyr::select(
      effects_metrics,
      metric_id = "metric_id", taxon = "taxon",
      duration_class = "duration_class", metric_role = "metric_role",
      effects_metric = "effects_metric",
      endpoint_description = "endpoint_description",
      effects_metric_status = "effects_metric_status"
    ),
    by = "taxon",
    relationship = "many-to-many"
  )
  grid <- dplyr::cross_join(
    grid, tibble::tibble(diet_fraction = diet_fractions)
  )

  grid$food_intake_g_dw_per_day <- grid$food_intake_g_dw_per_day
  grid$seeds_required_full_diet <- seeds_required_per_day(
    grid$food_intake_g_dw_per_day, grid$seed_mass_g, 1
  )
  grid$seeds_required_per_day <- seeds_required_per_day(
    grid$food_intake_g_dw_per_day, grid$seed_mass_g, grid$diet_fraction
  )
  grid$ede_full_diet <- estimated_daily_exposure(
    grid$concentration_mg_per_kg_seed, grid$food_intake_g_dw_per_day,
    grid$body_weight_g, 1
  )
  grid$initial_dose_mg_kg_bw_day <- estimated_daily_exposure(
    grid$concentration_mg_per_kg_seed, grid$food_intake_g_dw_per_day,
    grid$body_weight_g, grid$diet_fraction
  )

  # Accessible seed pool. Birds are assessed on surface seed only
  # (ASSUMPTION-019). Where a receptor is not restricted to surface seed
  # (ASSUMPTION-020), the accessible pool is the full sown density.
  grid$accessible_seeds_per_m2 <- stbam_ifelse(
    grid$surface_seed_only, grid$initial_surface_seeds_per_m2, grid$seeds_per_m2
  )
  grid$accessible_pool_basis <- stbam_ifelse(
    grid$surface_seed_only, "SURFACE_SEED_ONLY", "SURFACE_PLUS_BURIED"
  )
  grid
}
