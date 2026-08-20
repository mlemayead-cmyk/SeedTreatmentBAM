# Regulatory table construction.
#
# These functions shape canonical results into the published table layouts.
# They perform NO scientific calculation. The table shown in the dashboard and
# the table written to Word and CSV are built by the same function, so they
# cannot diverge.

#' Format a value to a fixed number of significant digits
#'
#' Regulatory tables use significant digits rather than decimal places, so that
#' small and large values are both reported meaningfully.
#'
#' @param x Numeric vector.
#' @param digits Significant digits.
#' @param big_mark Thousands separator.
#' @return Character vector.
#' @export
fmt_sig <- function(x, digits = 3, big_mark = ",") {
  vapply(x, function(value) {
    if (is.na(value)) return("-")
    if (is.infinite(value)) return(if (value > 0) "no limit" else "-")
    if (value == 0) return("0")
    rounded <- signif(value, digits)
    # Scientific notation only where fixed notation would be unreadable.
    scientific <- abs(rounded) < 1e-4 || abs(rounded) >= 1e12
    format(rounded, big.mark = if (scientific) "" else big_mark,
           scientific = scientific, trim = TRUE, drop0trailing = TRUE,
           digits = digits)
  }, character(1))
}

#' Format a numeric range as a single cell
#'
#' Published tables report ranges across the agronomic bounds. Where both ends
#' round to the same value at the reporting precision, a single value is shown
#' rather than a misleading "5 - 5".
#'
#' @param low,high Numeric vectors.
#' @param digits Significant digits.
#' @return Character vector.
#' @export
fmt_range <- function(low, high, digits = 3) {
  lo <- fmt_sig(low, digits)
  hi <- fmt_sig(high, digits)
  ifelse(lo == hi, lo, paste0(lo, " - ", hi))
}

#' @noRd
receptor_label <- function(taxon, size_class, body_weight_g) {
  sprintf("%s %s (%g g)",
          tools::toTitleCase(size_class),
          ifelse(taxon == "bird", "bird", "mammal"),
          body_weight_g)
}

#' Table: seed availability and search area
#'
#' Reproduces the layout of the published surface-seed availability tables
#' (assessment Tables 21-23 for birds), built from canonical results.
#'
#' @param scenario_summary Output of [build_scenario_summary].
#' @return A tibble ready for display or export.
#' @export
table_seed_availability <- function(scenario_summary) {
  data <- scenario_summary[scenario_summary$diet_fraction == 1, ]
  if (nrow(data) == 0L) {
    stbam_abort("Seed availability is tabulated at a 100 percent diet; the ",
                "supplied summary contains no such rows.")
  }
  grouped <- dplyr::summarise(
    dplyr::group_by(data, .data$crop, .data$planting_method_label,
                    .data$receptor_id, .data$taxon, .data$size_class,
                    .data$body_weight_g, .data$msa_m2),
    surface_low = min(.data$initial_surface_seeds_per_m2),
    surface_high = max(.data$initial_surface_seeds_per_m2),
    area_per_seed_low = min(.data$area_per_surface_seed_m2),
    area_per_seed_high = max(.data$area_per_surface_seed_m2),
    seeds_in_msa_low = min(.data$initial_available_seeds_within_msa),
    seeds_in_msa_high = max(.data$initial_available_seeds_within_msa),
    feasible_low = min(.data$initial_max_feasible_diet_fraction),
    feasible_high = max(.data$initial_max_feasible_diet_fraction),
    days_low = min(.data$days_at_full_diet_available),
    days_high = max(.data$days_at_full_diet_available),
    .groups = "drop"
  )

  tibble::tibble(
    Crop = grouped$crop,
    `Seeding method` = grouped$planting_method_label,
    Receptor = receptor_label(grouped$taxon, grouped$size_class,
                              grouped$body_weight_g),
    `Surface seed density (seeds/m2)` = fmt_range(grouped$surface_low,
                                                  grouped$surface_high),
    `Mean area per surface seed (m2/seed)` = fmt_range(
      grouped$area_per_seed_low, grouped$area_per_seed_high, digits = 3
    ),
    `Maximum search area (m2)` = fmt_sig(grouped$msa_m2),
    `Seeds within search area` = fmt_range(grouped$seeds_in_msa_low,
                                           grouped$seeds_in_msa_high),
    `Diet as treated seed available (%)` = fmt_range(
      grouped$feasible_low * 100, grouped$feasible_high * 100
    ),
    `Days at or above a full diet` = fmt_range(grouped$days_low,
                                               grouped$days_high)
  )
}

#' Table: exposure and seed numbers by dietary fraction
#'
#' Reproduces the layout of the published dose tables (assessment Tables 24-26
#' for birds).
#'
#' @param scenario_summary Output of [build_scenario_summary].
#' @return A tibble ready for display or export.
#' @export
table_exposure_by_diet <- function(scenario_summary) {
  grouped <- dplyr::summarise(
    dplyr::group_by(scenario_summary, .data$crop, .data$rate_level,
                    .data$application_rate, .data$application_rate_unit,
                    .data$receptor_id, .data$taxon, .data$size_class,
                    .data$body_weight_g, .data$diet_fraction),
    dose = max(.data$initial_dose_mg_kg_bw_day),
    seeds_low = min(.data$seeds_required_per_day),
    seeds_high = max(.data$seeds_required_per_day),
    dose_per_seed_low = min(.data$dose_per_seed_mg),
    dose_per_seed_high = max(.data$dose_per_seed_mg),
    normalised_low = min(.data$dose_per_seed_mg / (.data$body_weight_g / 1000)),
    normalised_high = max(.data$dose_per_seed_mg / (.data$body_weight_g / 1000)),
    .groups = "drop"
  )
  grouped <- dplyr::arrange(grouped, .data$crop, .data$receptor_id,
                            dplyr::desc(.data$application_rate),
                            dplyr::desc(.data$diet_fraction))

  tibble::tibble(
    Crop = grouped$crop,
    `Application rate` = paste(fmt_sig(grouped$application_rate),
                               grouped$application_rate_unit),
    Receptor = receptor_label(grouped$taxon, grouped$size_class,
                              grouped$body_weight_g),
    `Treated seed in diet (%)` = fmt_sig(grouped$diet_fraction * 100),
    `Estimated daily dose (mg a.i./kg bw/d)` = fmt_sig(grouped$dose),
    `Number of seeds per day` = fmt_range(grouped$seeds_low, grouped$seeds_high),
    `Dose per seed (mg a.i./seed)` = fmt_range(grouped$dose_per_seed_low,
                                               grouped$dose_per_seed_high),
    `Dose per seed (mg a.i./kg bw)` = fmt_range(grouped$normalised_low,
                                                grouped$normalised_high)
  )
}

#' Table: risk quotients and duration above the effects metric
#'
#' Reproduces the layout of the published duration tables (assessment
#' Tables 27-29 for birds).
#'
#' @param scenario_summary Output of [build_scenario_summary].
#' @return A tibble ready for display or export.
#' @export
table_risk_and_duration <- function(scenario_summary) {
  grouped <- dplyr::summarise(
    dplyr::group_by(scenario_summary, .data$crop, .data$rate_level,
                    .data$application_rate, .data$application_rate_unit,
                    .data$receptor_id, .data$taxon, .data$size_class,
                    .data$body_weight_g, .data$diet_fraction,
                    .data$metric_id, .data$duration_class, .data$metric_role,
                    .data$effects_metric),
    dose = max(.data$initial_dose_mg_kg_bw_day),
    rq = max(.data$initial_rq),
    days = max(.data$days_above_loc),
    threshold = max(.data$threshold_diet_fraction_pct),
    .groups = "drop"
  )
  grouped <- dplyr::arrange(grouped, .data$crop, .data$receptor_id,
                            .data$duration_class,
                            dplyr::desc(.data$application_rate),
                            dplyr::desc(.data$diet_fraction))

  tibble::tibble(
    Crop = grouped$crop,
    `Application rate` = paste(fmt_sig(grouped$application_rate),
                               grouped$application_rate_unit),
    Receptor = receptor_label(grouped$taxon, grouped$size_class,
                              grouped$body_weight_g),
    `Treated seed in diet (%)` = fmt_sig(grouped$diet_fraction * 100),
    `Exposure type` = tools::toTitleCase(grouped$duration_class),
    `Effects metric` = grouped$metric_id,
    `Effects metric value (mg a.i./kg bw/d)` = fmt_sig(grouped$effects_metric),
    `Estimated daily dose (mg a.i./kg bw/d)` = fmt_sig(grouped$dose),
    `Risk quotient` = fmt_sig(grouped$rq),
    `Days at or above the metric` = fmt_sig(grouped$days),
    `Diet at the metric (%)` = fmt_sig(grouped$threshold)
  )
}

#' Table: exposure feasibility
#'
#' Presents the feasibility diagnostic separately from the calculated
#' regulatory exposure, as required by specification section 10.3.
#'
#' @param scenario_summary Output of [build_scenario_summary].
#' @return A tibble ready for display or export.
#' @export
table_exposure_feasibility <- function(scenario_summary) {
  grouped <- dplyr::summarise(
    dplyr::group_by(scenario_summary, .data$crop, .data$planting_method_label,
                    .data$rate_level, .data$receptor_id, .data$taxon,
                    .data$size_class, .data$body_weight_g, .data$msa_m2,
                    .data$diet_fraction),
    seeds_needed_low = min(.data$seeds_required_per_day),
    seeds_needed_high = max(.data$seeds_required_per_day),
    available_low = min(.data$initial_available_seeds_within_msa),
    available_high = max(.data$initial_available_seeds_within_msa),
    area_low = min(.data$initial_required_search_area_m2),
    area_high = max(.data$initial_required_search_area_m2),
    feasible_low = min(.data$initial_max_feasible_diet_fraction),
    feasible_high = max(.data$initial_max_feasible_diet_fraction),
    any_feasible = any(.data$diet_fraction_is_feasible_at_sowing),
    all_feasible = all(.data$diet_fraction_is_feasible_at_sowing),
    days_feasible_low = min(.data$days_assumed_diet_feasible),
    days_feasible_high = max(.data$days_assumed_diet_feasible),
    .groups = "drop"
  )

  verdict <- ifelse(
    grouped$all_feasible, "Obtainable",
    ifelse(grouped$any_feasible, "Obtainable for some bounds", "Not obtainable")
  )

  tibble::tibble(
    Crop = grouped$crop,
    `Seeding method` = grouped$planting_method_label,
    Receptor = receptor_label(grouped$taxon, grouped$size_class,
                              grouped$body_weight_g),
    `Treated seed in diet (%)` = fmt_sig(grouped$diet_fraction * 100),
    `Seeds needed per day` = fmt_range(grouped$seeds_needed_low,
                                       grouped$seeds_needed_high),
    `Seeds available in search area` = fmt_range(grouped$available_low,
                                                 grouped$available_high),
    `Search area required (m2)` = fmt_range(grouped$area_low, grouped$area_high),
    `Maximum search area (m2)` = fmt_sig(grouped$msa_m2),
    `Maximum obtainable diet (%)` = fmt_range(grouped$feasible_low * 100,
                                              grouped$feasible_high * 100),
    `Days the modelled diet is obtainable` = fmt_range(
      grouped$days_feasible_low, grouped$days_feasible_high
    ),
    `Feasibility at sowing` = verdict
  )
}

#' Registry of the official tables the model can produce
#' @export
STBAM_TABLES <- list(
  seed_availability = list(
    builder = "table_seed_availability",
    title = "Estimated treated-seed availability and search area",
    orientation = "landscape",
    notes = c(
      "Surface seed density is the sown seed count multiplied by the proportion of seed remaining on the surface for the planting method.",
      "Ranges span the seeding-rate and seed-mass bounds evaluated for the crop.",
      "Days at or above a full diet use the surface-seed disappearance half-life, not the residue dissipation half-life."
    )
  ),
  exposure_by_diet = list(
    builder = "table_exposure_by_diet",
    title = "Estimated daily dose and treated-seed numbers by dietary fraction",
    orientation = "landscape",
    notes = c(
      "Estimated daily dose is the seed concentration multiplied by the food ingestion rate, divided by body weight, times the dietary fraction.",
      "Food ingestion rates are Nagy allometric regressions on a dry-weight diet basis.",
      "Seed numbers range across the seed-mass bounds; the dose does not depend on seed mass for a rate expressed per unit seed mass."
    )
  ),
  risk_and_duration = list(
    builder = "table_risk_and_duration",
    title = "Risk quotients and duration above the effects metric",
    orientation = "landscape",
    notes = c(
      "The risk quotient is the estimated daily dose divided by the effects metric.",
      "Duration above the metric assumes first-order residue dissipation and is calculated as DT50 x log2(dose / metric).",
      "Screening and refined-additional effects metrics are reported separately and are not combined."
    )
  ),
  exposure_feasibility = list(
    builder = "table_exposure_feasibility",
    title = "Exposure feasibility within the maximum search area",
    orientation = "landscape",
    notes = c(
      "This table is a plausibility diagnostic. It does not cap the calculated regulatory exposure reported in the dose and risk tables.",
      "The search area required is the seeds needed per day divided by the accessible surface seed density.",
      "Feasibility at sowing compares the assumed dietary fraction with the maximum obtainable dietary fraction on the day of sowing."
    )
  )
)

#' Build one official table by name
#'
#' The single entry point used by the dashboard, the Word exporter and the CSV
#' exporter, so all three necessarily show the same numbers.
#'
#' @param table_id A name of [STBAM_TABLES].
#' @param scenario_summary Output of [build_scenario_summary].
#' @return A tibble.
#' @export
build_official_table <- function(table_id, scenario_summary) {
  check_choice(table_id, "table_id", names(STBAM_TABLES))
  builder <- get(STBAM_TABLES[[table_id]]$builder, mode = "function")
  builder(scenario_summary)
}
