# Exposure, risk quotients and duration above an effects metric.
#
# Specification section 9.

#' Estimated daily exposure from the seed concentration
#'
#' `EDE = C_seed * FIR / BW * p_diet`. The g/g ratio is dimensionless, so
#' mg/kg seed carries through to mg/kg bw/day with no numeric factor.
#'
#' Note this does not depend on seed mass when the rate is expressed per unit
#' seed mass. Seed mass affects seed counts and availability, not dose.
#'
#' @param concentration_mg_per_kg_seed Seed concentration, mg a.i./kg seed.
#' @param food_intake_g_dw_per_day Food ingestion rate, g dry weight/day.
#' @param body_weight_g Body weight, g.
#' @param diet_fraction Fraction of the daily diet that is treated seed, 0-1.
#' @return Estimated daily exposure, mg a.i./kg bw/day.
#' @export
estimated_daily_exposure <- function(concentration_mg_per_kg_seed,
                                     food_intake_g_dw_per_day,
                                     body_weight_g, diet_fraction = 1) {
  check_numeric(concentration_mg_per_kg_seed, "concentration_mg_per_kg_seed",
                min = 0)
  check_numeric(food_intake_g_dw_per_day, "food_intake_g_dw_per_day", min = 0)
  check_numeric(body_weight_g, "body_weight_g", min = 0, exclusive_min = TRUE)
  check_numeric(diet_fraction, "diet_fraction", min = 0, max = 1)
  check_recyclable(concentration_mg_per_kg_seed, food_intake_g_dw_per_day,
                   body_weight_g, diet_fraction)
  concentration_mg_per_kg_seed * food_intake_g_dw_per_day / body_weight_g *
    diet_fraction
}

#' Estimated daily exposure from a seed count and a per-seed dose
#'
#' Algebraically identical to [estimated_daily_exposure]; provided as an
#' independent formulation and asserted equal in the test suite.
#'
#' @param seeds_consumed_per_day Seeds consumed, seeds/day.
#' @param dose_per_seed_mg Dose per seed, mg a.i./seed.
#' @param body_weight_g Body weight, g.
#' @return Estimated daily exposure, mg a.i./kg bw/day.
#' @export
daily_ai_intake_dose <- function(seeds_consumed_per_day, dose_per_seed_mg,
                                 body_weight_g) {
  check_numeric(seeds_consumed_per_day, "seeds_consumed_per_day", min = 0)
  check_numeric(dose_per_seed_mg, "dose_per_seed_mg", min = 0)
  check_numeric(body_weight_g, "body_weight_g", min = 0, exclusive_min = TRUE)
  check_recyclable(seeds_consumed_per_day, dose_per_seed_mg, body_weight_g)
  seeds_consumed_per_day * dose_per_seed_mg / (body_weight_g / 1000)
}

#' Dose over time
#'
#' Declines with residue dissipation only. Whether the assumed dietary fraction
#' remains physically attainable at time `t` is a separate feasibility question
#' and is deliberately NOT applied here (specification section 10.3).
#'
#' @param initial_dose_mg_kg_bw_day Dose at sowing, mg a.i./kg bw/day.
#' @param day Days since sowing.
#' @param residue_dt50_days Residue dissipation half-life, days.
#' @return Dose, mg a.i./kg bw/day.
#' @export
daily_dose_over_time <- function(initial_dose_mg_kg_bw_day, day,
                                 residue_dt50_days) {
  check_numeric(initial_dose_mg_kg_bw_day, "initial_dose_mg_kg_bw_day", min = 0)
  check_recyclable(initial_dose_mg_kg_bw_day, day, residue_dt50_days)
  initial_dose_mg_kg_bw_day * first_order_remaining(day, residue_dt50_days)
}

#' Risk quotient
#'
#' @param dose_mg_kg_bw_day Dose, mg a.i./kg bw/day.
#' @param effects_metric Effects metric, mg a.i./kg bw/day.
#' @return Risk quotient, dimensionless.
#' @export
risk_quotient <- function(dose_mg_kg_bw_day, effects_metric) {
  check_numeric(dose_mg_kg_bw_day, "dose_mg_kg_bw_day", min = 0)
  check_numeric(effects_metric, "effects_metric", min = 0, exclusive_min = TRUE)
  check_recyclable(dose_mg_kg_bw_day, effects_metric)
  dose_mg_kg_bw_day / effects_metric
}

#' Number of days the dose remains at or above an effects metric
#'
#' Solves `Dose(t) = M` under first-order residue dissipation. Returns 0 when
#' the initial dose does not reach the metric; never negative.
#'
#' @param initial_dose_mg_kg_bw_day Dose at sowing, mg a.i./kg bw/day.
#' @param effects_metric Effects metric, mg a.i./kg bw/day.
#' @param residue_dt50_days Residue dissipation half-life, days.
#' @return Days above the metric. `Inf` if residues do not dissipate.
#' @export
duration_above_effect_metric <- function(initial_dose_mg_kg_bw_day,
                                         effects_metric, residue_dt50_days) {
  check_numeric(initial_dose_mg_kg_bw_day, "initial_dose_mg_kg_bw_day", min = 0)
  check_numeric(effects_metric, "effects_metric", min = 0, exclusive_min = TRUE)
  check_numeric(residue_dt50_days, "residue_dt50_days", min = 0,
                exclusive_min = TRUE, allow_inf = TRUE)
  check_recyclable(initial_dose_mg_kg_bw_day, effects_metric, residue_dt50_days)

  exceeds <- initial_dose_mg_kg_bw_day > effects_metric
  finite_duration <- residue_dt50_days *
    log2(pmax(initial_dose_mg_kg_bw_day, effects_metric) / effects_metric)
  stbam_ifelse(
    exceeds,
    stbam_ifelse(is.infinite(residue_dt50_days), Inf, finite_duration),
    0
  )
}

#' Dietary fraction at which an effects metric is exactly reached
#'
#' @param ede_full_diet Estimated daily exposure at a 100 percent treated-seed
#'   diet, mg a.i./kg bw/day.
#' @param effects_metric Effects metric, mg a.i./kg bw/day.
#' @return Threshold dietary fraction, percent. `Inf` where the metric is
#'   unreachable at any dietary fraction.
#' @export
threshold_diet_fraction_pct <- function(ede_full_diet, effects_metric) {
  check_numeric(ede_full_diet, "ede_full_diet", min = 0)
  check_numeric(effects_metric, "effects_metric", min = 0, exclusive_min = TRUE)
  check_recyclable(ede_full_diet, effects_metric)
  stbam_ifelse(ede_full_diet > 0,
               effects_metric / pmax(ede_full_diet, .Machine$double.xmin) * 100,
               Inf)
}

#' Number of seeds that must be eaten to reach an effects metric
#'
#' @param effects_metric Effects metric, mg a.i./kg bw/day.
#' @param body_weight_g Body weight, g.
#' @param dose_per_seed_mg Dose per seed, mg a.i./seed.
#' @return Seeds required to reach the metric. `Inf` for untreated seed.
#' @export
seeds_to_effect_metric <- function(effects_metric, body_weight_g,
                                   dose_per_seed_mg) {
  check_numeric(effects_metric, "effects_metric", min = 0, exclusive_min = TRUE)
  check_numeric(body_weight_g, "body_weight_g", min = 0, exclusive_min = TRUE)
  check_numeric(dose_per_seed_mg, "dose_per_seed_mg", min = 0)
  check_recyclable(effects_metric, body_weight_g, dose_per_seed_mg)
  stbam_ifelse(
    dose_per_seed_mg > 0,
    effects_metric * (body_weight_g / 1000) /
      pmax(dose_per_seed_mg, .Machine$double.xmin),
    Inf
  )
}
