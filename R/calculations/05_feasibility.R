# Exposure feasibility: maximum search area analysis.
#
# Specification section 10.
#
# IMPORTANT. These functions answer "could an animal realistically obtain this
# much treated seed?". They are a diagnostic, not a cap on the regulatory
# exposure calculation. Nothing in this file modifies dose or RQ.

#' Treated seeds available within the maximum search area
#'
#' @param surface_seeds_per_m2 Surface seed density, seeds/m2.
#' @param msa_m2 Maximum search area, m2.
#' @return Seeds available within the search area.
#' @export
available_seed_within_msa <- function(surface_seeds_per_m2, msa_m2) {
  check_numeric(surface_seeds_per_m2, "surface_seeds_per_m2", min = 0)
  check_numeric(msa_m2, "msa_m2", min = 0, exclusive_min = TRUE)
  check_recyclable(surface_seeds_per_m2, msa_m2)
  surface_seeds_per_m2 * msa_m2
}

#' Search area required to obtain a required number of seeds
#'
#' @param seeds_required_per_day Seeds required, seeds/day.
#' @param surface_seeds_per_m2 Surface seed density, seeds/m2.
#' @return Required search area, m2. `Inf` where no surface seed remains and
#'   seed is still required; 0 where no seed is required.
#' @export
required_search_area <- function(seeds_required_per_day, surface_seeds_per_m2) {
  check_numeric(seeds_required_per_day, "seeds_required_per_day", min = 0)
  check_numeric(surface_seeds_per_m2, "surface_seeds_per_m2", min = 0)
  check_recyclable(seeds_required_per_day, surface_seeds_per_m2)
  stbam_ifelse(
    seeds_required_per_day == 0, 0,
    stbam_ifelse(
      surface_seeds_per_m2 > 0,
      seeds_required_per_day / pmax(surface_seeds_per_m2, .Machine$double.xmin),
      Inf
    )
  )
}

#' Maximum dietary fraction physically obtainable within the search area
#'
#' Expressed as a fraction of the full daily diet. Values above 1 mean more
#' than a full daily diet of treated seed is available.
#'
#' @param surface_seeds_per_m2 Surface seed density, seeds/m2.
#' @param msa_m2 Maximum search area, m2.
#' @param food_intake_g_dw_per_day Food ingestion rate, g dry weight/day.
#' @param seed_mass_g Individual seed mass, g/seed.
#' @return Maximum feasible dietary fraction, dimensionless (not capped at 1).
#' @export
maximum_feasible_diet_fraction <- function(surface_seeds_per_m2, msa_m2,
                                           food_intake_g_dw_per_day,
                                           seed_mass_g) {
  check_numeric(food_intake_g_dw_per_day, "food_intake_g_dw_per_day", min = 0,
                exclusive_min = TRUE)
  check_numeric(seed_mass_g, "seed_mass_g", min = 0, exclusive_min = TRUE)
  available <- available_seed_within_msa(surface_seeds_per_m2, msa_m2)
  check_recyclable(available, food_intake_g_dw_per_day, seed_mass_g)
  seeds_for_full_diet <- food_intake_g_dw_per_day / seed_mass_g
  available / seeds_for_full_diet
}

#' Number of days for which a given dietary fraction remains obtainable
#'
#' Uses the SURFACE-SEED half-life, because this is an availability question,
#' not a residue question.
#'
#' @param initial_max_feasible_diet_fraction Maximum feasible dietary fraction
#'   at sowing.
#' @param target_diet_fraction Dietary fraction of interest, 0-1. A target of
#'   0 requires no seed at all and is trivially obtainable for as long as the
#'   scenario is modelled (specification invariant 6 names `p_diet = 0` as a
#'   valid input; this function must accept it on the same terms as every
#'   other function in the exposure chain).
#' @param surface_seed_dt50_days Surface-seed disappearance half-life, days.
#' @return Days until the target fraction is no longer obtainable. 0 if it is
#'   never obtainable; `Inf` if surface seed does not decline, or if the
#'   target dietary fraction is 0.
#' @export
days_diet_fraction_feasible <- function(initial_max_feasible_diet_fraction,
                                        target_diet_fraction,
                                        surface_seed_dt50_days) {
  check_numeric(initial_max_feasible_diet_fraction,
                "initial_max_feasible_diet_fraction", min = 0)
  check_numeric(target_diet_fraction, "target_diet_fraction", min = 0, max = 1)
  check_numeric(surface_seed_dt50_days, "surface_seed_dt50_days", min = 0,
                exclusive_min = TRUE, allow_inf = TRUE)
  check_recyclable(initial_max_feasible_diet_fraction, target_diet_fraction,
                   surface_seed_dt50_days)

  zero_target <- target_diet_fraction == 0
  # Divide by 1 instead of 0 for a zero target so the ratio is always
  # well-defined; the zero_target branch below discards it regardless.
  ratio <- initial_max_feasible_diet_fraction /
    stbam_ifelse(zero_target, 1, target_diet_fraction)
  result <- stbam_ifelse(
    ratio > 1,
    stbam_ifelse(is.infinite(surface_seed_dt50_days), Inf,
                 surface_seed_dt50_days * log2(pmax(ratio, 1))),
    0
  )
  stbam_ifelse(zero_target, Inf, result)
}

#' Is the assumed dietary fraction physically attainable?
#'
#' @param diet_fraction Assumed dietary fraction, 0-1.
#' @param max_feasible_diet_fraction Maximum feasible dietary fraction.
#' @return Logical vector.
#' @export
diet_fraction_is_feasible <- function(diet_fraction,
                                      max_feasible_diet_fraction) {
  check_numeric(diet_fraction, "diet_fraction", min = 0, max = 1)
  check_numeric(max_feasible_diet_fraction, "max_feasible_diet_fraction",
                min = 0)
  check_recyclable(diet_fraction, max_feasible_diet_fraction)
  max_feasible_diet_fraction >= diet_fraction
}

#' Which maximum-search-area term applies to a given taxon and duration class
#'
#' This is NOT a general "acute = short-term, chronic = long-term" rule
#' invented for this model. It is grounded directly in the source
#' assessment's own stated methodology (assessment paragraph `MAIN-P000209`,
#' review register `ASSUMPTION-012` through `ASSUMPTION-016`):
#'
#' \itemize{
#'   \item \strong{Birds always use the short-term MSA}, for both acute and
#'     chronic/reproductive characterization. The assessment explicitly
#'     states that a long-term MSA was "not considered" for birds, "because
#'     there was a paucity of evidence to suggest that observed effects on
#'     reproduction were due to a long-term exposure, as opposed to parental
#'     exposure occurring over [a] critical window within the reproductive
#'     cycle."
#'   \item \strong{Mammals use the short-term MSA for acute characterization
#'     and the long-term MSA for chronic/reproductive characterization.} The
#'     assessment attributes mammalian reproductive effects to prolonged
#'     parental exposure, unlike birds, and states this explicitly as the
#'     basis for applying a long-term MSA to mammals.
#' }
#'
#' A `receptor_parameters.csv` row for a bird nonetheless stores a
#' `msa_long_term_m2` value, and the existing manually-toggled `msa_term`
#' argument to [resolve_receptors] will honour a user's request for it if
#' asked (used by the pre-existing "Exposure feasibility" diagnostic, which
#' is a manual what-if tool and is unchanged by this function). This
#' function exists so that analyses which must follow the assessment's own
#' policy automatically -- rather than trust a manual toggle -- can do so
#' without guessing.
#'
#' @param taxon `"bird"` or `"mammal"`.
#' @param duration_class `"acute"` or `"chronic"`.
#' @return `"short"` or `"long"`.
#' @export
resolve_msa_term_for_metric <- function(taxon, duration_class) {
  check_choice(taxon, "taxon", c("bird", "mammal"))
  check_choice(duration_class, "duration_class", c("acute", "chronic"))
  check_recyclable(taxon, duration_class)
  stbam_ifelse(
    taxon == "bird", "short",
    stbam_ifelse(duration_class == "acute", "short", "long")
  )
}

#' Maximum treated seed a receptor could actually consume in a day
#'
#' Caps the number of seeds required to meet an assumed dietary fraction at
#' the number of treated seeds actually available within the applicable
#' maximum search area. Does **not** assume every available seed is eaten if
#' that would exceed the receptor's food requirement -- the receptor is never
#' modelled as consuming more than it needs, only ever less than it needs
#' when seed is scarce.
#'
#' @param seeds_required_per_day Seeds needed to meet the assumed dietary
#'   fraction, seeds/day (see [seeds_required_per_day]).
#' @param seeds_available_within_msa Treated seeds available within the
#'   applicable search area (see [available_seed_within_msa]).
#' @return Seeds actually obtainable, seeds/day. Never exceeds either input.
#' @export
max_obtainable_seeds_per_day <- function(seeds_required_per_day,
                                         seeds_available_within_msa) {
  check_numeric(seeds_required_per_day, "seeds_required_per_day", min = 0)
  check_numeric(seeds_available_within_msa, "seeds_available_within_msa",
                min = 0)
  check_recyclable(seeds_required_per_day, seeds_available_within_msa)
  pmin(seeds_required_per_day, seeds_available_within_msa)
}
