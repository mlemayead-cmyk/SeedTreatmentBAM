# Summary annotations for the maximum-obtainable-exposure figure.
#
# Peak risk quotients and the day each curve crosses the level of concern,
# computed from a daily_timecourse slice. Kept as a small, well-contained
# addition on top of the canonical daily_timecourse dataset built in
# 22_daily_timecourse.R -- this file adds no new calculation of its own
# beyond what is needed to summarise columns that dataset already computes.

#' Exact duration at or above LOC for maximum-obtainable RQ
#'
#' Maximum-obtainable RQ is piecewise first-order. While seed is abundant it
#' equals conditional RQ and declines at the residue DT50. Once availability
#' becomes binding it declines at the combined residue-plus-surface-seed rate.
#' This function solves the LOC crossing exactly rather than reading it from a
#' discrete plotting grid.
#'
#' @param conditional_rq0 Conditional 100%-diet RQ at sowing.
#' @param max_obtainable_rq0 Maximum-obtainable RQ at sowing.
#' @param initial_feasible_fraction Treated-seed diet fraction available within
#'   the applicable MSA at sowing (1 means a full diet).
#' @param surface_seed_dt50_days Surface-seed disappearance DT50, days.
#' @param residue_dt50_days Residue-per-seed dissipation DT50, days.
#' @param loc Applicable level-of-concern threshold.
#' @return Exact days at or above LOC; zero when LOC is not exceeded at sowing.
#' @export
duration_above_max_obtainable_rq <- function(
    conditional_rq0, max_obtainable_rq0, initial_feasible_fraction,
    surface_seed_dt50_days, residue_dt50_days,
    loc = STBAM_DEFAULT_LOC) {
  check_numeric(conditional_rq0, "conditional_rq0", min = 0)
  check_numeric(max_obtainable_rq0, "max_obtainable_rq0", min = 0)
  check_numeric(initial_feasible_fraction, "initial_feasible_fraction", min = 0)
  check_numeric(surface_seed_dt50_days, "surface_seed_dt50_days", min = 0,
                exclusive_min = TRUE, allow_inf = TRUE)
  check_numeric(residue_dt50_days, "residue_dt50_days", min = 0,
                exclusive_min = TRUE, allow_inf = TRUE)
  check_numeric(loc, "loc", min = 0, exclusive_min = TRUE)
  check_recyclable(conditional_rq0, max_obtainable_rq0,
                   initial_feasible_fraction, surface_seed_dt50_days,
                   residue_dt50_days, loc)
  if (any(max_obtainable_rq0 > conditional_rq0 +
          sqrt(.Machine$double.eps) * pmax(1, conditional_rq0))) {
    stbam_abort("`max_obtainable_rq0` cannot exceed `conditional_rq0`.")
  }

  scalar <- function(cond0, max0, feasible0, surface_dt50, residue_dt50,
                     threshold) {
    if (max0 <= threshold) return(0)
    seed_limit_day <- if (feasible0 > 1) {
      surface_dt50 * log2(feasible0)
    } else {
      0
    }
    conditional_crossing <- if (cond0 > threshold) {
      residue_dt50 * log2(cond0 / threshold)
    } else {
      0
    }
    if (conditional_crossing <= seed_limit_day) return(conditional_crossing)

    rq_at_seed_limit <- if (seed_limit_day > 0) {
      cond0 * first_order_remaining(seed_limit_day, residue_dt50)
    } else {
      max0
    }
    combined_dt50 <- combined_surface_ai_dt50(surface_dt50, residue_dt50)
    seed_limit_day + combined_dt50 * log2(rq_at_seed_limit / threshold)
  }

  as.numeric(mapply(
    scalar, conditional_rq0, max_obtainable_rq0, initial_feasible_fraction,
    surface_seed_dt50_days, residue_dt50_days, loc,
    SIMPLIFY = TRUE, USE.NAMES = FALSE
  ))
}

#' Summarise conditional versus maximum-obtainable exposure
#'
#' Reads a slice of [build_daily_timecourse] output (one or more
#' scenario/receptor/metric groups; the `diet_fraction == 1` rows are used)
#' and computes the annotations shown alongside the principal
#' maximum-obtainable-exposure figure: peak risk quotients, the day each
#' curve first falls below the level of concern, and the day 100%, 50% and
#' 25% of the assumed diet first become unobtainable under the assessment's
#' own MSA policy (specification section 10.4).
#'
#' The conditional (100%-diet) crossing day and the diet-fraction-unobtainable
#' days are **exact closed-form results**, computed with the same
#' [duration_above_effect_metric] and [days_diet_fraction_feasible] functions
#' the rest of the model uses -- no new equation is introduced. The
#' maximum-obtainable RQ crossing is solved exactly as a piecewise first-order
#' curve by [duration_above_max_obtainable_rq].
#'
#' @param timecourse Output of [build_daily_timecourse], one or more
#'   scenario/receptor/metric groups, including the `diet_fraction == 1` rows.
#' @return A tibble, one row per `scenario_id` x `receptor_id` x `metric_id`.
#' @export
summarise_max_obtainable_exposure <- function(timecourse) {
  full_diet <- timecourse[timecourse$diet_fraction == 1, ]
  if (nrow(full_diet) == 0L) {
    stbam_abort("summarise_max_obtainable_exposure() requires diet_fraction ",
                "== 1 rows; none were supplied.")
  }

  group_key <- interaction(
    full_diet$scenario_id, full_diet$receptor_id, full_diet$metric_id,
    drop = TRUE, lex.order = TRUE
  )
  group_indices <- split(seq_len(nrow(full_diet)), group_key)
  rows <- vector("list", length(group_indices))

  for (i in seq_along(group_indices)) {
    one <- full_diet[group_indices[[i]], ]
    one <- one[order(one$day), ]
    if (!any(one$day == 0)) {
      stbam_abort("summarise_max_obtainable_exposure() requires a day 0 row ",
                  "for every scenario/receptor/metric group.")
    }
    day0 <- one[one$day == 0, ][1, ]

    rows[[i]] <- tibble::tibble(
      scenario_id = day0$scenario_id,
      workbook = day0$workbook,
      crop = day0$crop,
      rate_level = day0$rate_level,
      application_rate = day0$application_rate,
      application_rate_unit = day0$application_rate_unit,
      planting_method = day0$planting_method,
      planting_method_label = day0$planting_method_label,
      seeding_rate_bound = day0$seeding_rate_bound,
      seed_mass_bound = day0$seed_mass_bound,
      tkw_g_per_1000 = day0$tkw_g_per_1000,
      seeding_rate_kg_per_ha = day0$seeding_rate_kg_per_ha,
      seeds_per_m2 = day0$seeds_per_m2,
      surface_seed_fraction = day0$surface_seed_fraction,
      initial_surface_seeds_per_m2 = day0$initial_surface_seeds_per_m2,
      field_rate_g_ai_per_ha = day0$field_rate_g_ai_per_ha,
      receptor_id = day0$receptor_id,
      metric_id = day0$metric_id,
      taxon = day0$taxon,
      size_class = day0$size_class,
      body_weight_g = day0$body_weight_g,
      food_intake_g_dw_per_day = day0$food_intake_g_dw_per_day,
      duration_class = day0$duration_class,
      metric_role = day0$metric_role,
      effects_metric = day0$effects_metric,
      residue_dt50_days = day0$residue_dt50_days,
      surface_seed_dt50_days = day0$surface_seed_dt50_days,
      msa_m2 = day0$max_obtainable_msa_m2,
      msa_term = day0$max_obtainable_msa_term,

      peak_conditional_rq = max(one$rq),
      peak_max_obtainable_rq = max(one$max_obtainable_rq),
      conditional_exceeds_loc = max(one$rq) >= STBAM_DEFAULT_LOC,
      max_obtainable_exceeds_loc =
        max(one$max_obtainable_rq) >= STBAM_DEFAULT_LOC,
      day0_seeds_available_within_msa = day0$max_obtainable_seeds_within_msa,
      day0_seeds_required_100pct_diet = day0$seeds_required_per_day,
      day0_max_obtainable_seeds_consumed = day0$max_obtainable_seeds_per_day,

      day_conditional_below_loc = duration_above_effect_metric(
        day0$initial_dose_mg_kg_bw_day,
        day0$effects_metric * STBAM_DEFAULT_LOC,
        day0$residue_dt50_days
      ),
      day_max_obtainable_below_loc = duration_above_max_obtainable_rq(
        day0$rq, day0$max_obtainable_rq,
        day0$max_obtainable_diet_fraction,
        day0$surface_seed_dt50_days, day0$residue_dt50_days,
        STBAM_DEFAULT_LOC
      ),
      days_above_loc_conditional = duration_above_effect_metric(
        day0$initial_dose_mg_kg_bw_day,
        day0$effects_metric * STBAM_DEFAULT_LOC,
        day0$residue_dt50_days
      ),
      days_above_loc_max_obtainable = duration_above_max_obtainable_rq(
        day0$rq, day0$max_obtainable_rq,
        day0$max_obtainable_diet_fraction,
        day0$surface_seed_dt50_days, day0$residue_dt50_days,
        STBAM_DEFAULT_LOC
      ),

      day_100pct_diet_unobtainable = days_diet_fraction_feasible(
        day0$max_obtainable_diet_fraction, 1, day0$surface_seed_dt50_days
      ),
      day_50pct_diet_unobtainable = days_diet_fraction_feasible(
        day0$max_obtainable_diet_fraction, 0.50, day0$surface_seed_dt50_days
      ),
      day_25pct_diet_unobtainable = days_diet_fraction_feasible(
        day0$max_obtainable_diet_fraction, 0.25, day0$surface_seed_dt50_days
      ),
      parameter_set = day0$parameter_set,
      provenance_class = day0$provenance_class
    )
  }
  dplyr::bind_rows(rows)
}
