# Receptor food requirement and seed intake.
#
# Specification section 8.

#' Food ingestion rate from an allometric regression
#'
#' `FIR = a * BW^b`, on a DRY WEIGHT diet basis. The model applies no
#' dry-to-fresh conversion because none is specified in the assessment or the
#' source workbook (specification section 14).
#'
#' @param body_weight_g Body weight, g.
#' @param coefficient_a Regression coefficient `a`.
#' @param exponent_b Regression exponent `b`.
#' @return Food ingestion rate, g dry weight diet/day.
#' @export
food_requirement <- function(body_weight_g, coefficient_a, exponent_b) {
  check_numeric(body_weight_g, "body_weight_g", min = 0, exclusive_min = TRUE)
  check_numeric(coefficient_a, "coefficient_a", min = 0, exclusive_min = TRUE)
  check_numeric(exponent_b, "exponent_b")
  check_recyclable(body_weight_g, coefficient_a, exponent_b)
  coefficient_a * body_weight_g^exponent_b
}

#' Seeds required per day to meet a dietary fraction
#'
#' Time-invariant: this is what the animal needs, not what is available.
#'
#' @param food_intake_g_dw_per_day Food ingestion rate, g dry weight/day.
#' @param seed_mass_g Individual seed mass, g/seed.
#' @param diet_fraction Fraction of the daily diet that is treated seed, 0-1.
#' @return Seeds required, seeds/day.
#' @export
seeds_required_per_day <- function(food_intake_g_dw_per_day, seed_mass_g,
                                   diet_fraction = 1) {
  check_numeric(food_intake_g_dw_per_day, "food_intake_g_dw_per_day", min = 0)
  check_numeric(seed_mass_g, "seed_mass_g", min = 0, exclusive_min = TRUE)
  check_numeric(diet_fraction, "diet_fraction", min = 0, max = 1)
  check_recyclable(food_intake_g_dw_per_day, seed_mass_g, diet_fraction)
  (food_intake_g_dw_per_day / seed_mass_g) * diet_fraction
}
