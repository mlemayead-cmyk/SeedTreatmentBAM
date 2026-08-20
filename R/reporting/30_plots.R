# Reusable scientific plots.
#
# Plotting functions consume canonical results only. They contain NO scientific
# calculation: if a quantity is not already a column of the canonical data, it
# does not belong here.

#' Shared plot theme
#' @export
theme_stbam <- function(base_size = 12) {
  ggplot2::theme_bw(base_size = base_size) +
    ggplot2::theme(
      panel.grid.minor = ggplot2::element_blank(),
      panel.grid.major = ggplot2::element_line(linewidth = 0.25,
                                               colour = "grey88"),
      strip.background = ggplot2::element_rect(fill = "grey94",
                                               colour = "grey70"),
      strip.text = ggplot2::element_text(face = "bold", size = base_size * 0.85),
      plot.title = ggplot2::element_text(face = "bold", size = base_size * 1.1),
      plot.subtitle = ggplot2::element_text(colour = "grey30",
                                            size = base_size * 0.9),
      plot.caption = ggplot2::element_text(colour = "grey40",
                                           size = base_size * 0.75, hjust = 0),
      legend.position = "bottom",
      legend.key = ggplot2::element_blank(),
      legend.text = ggplot2::element_text(size = base_size * 0.8)
    )
}

#' Wrap a colour legend onto two rows so long series labels are not clipped
#'
#' Kept separate from [theme_stbam] because a `guides()` specification is not a
#' theme and cannot be added to one.
#' @noRd
stbam_legend_guide <- function(rows = 2) {
  ggplot2::guides(colour = ggplot2::guide_legend(nrow = rows, byrow = TRUE))
}

#' Wrap long title and caption text so it is not clipped
#' @noRd
wrap_text <- function(x, width = 95) {
  if (is.null(x) || !is.character(x)) {
    return(x)
  }
  paste(strwrap(x, width = width), collapse = "\n")
}

#' Colour-blind-safe palette used across every model plot
#' @export
STBAM_PALETTE <- c(
  "#0072B2", "#D55E00", "#009E73", "#CC79A7",
  "#E69F00", "#56B4E9", "#8C564B", "#999999"
)

#' @noRd
stbam_colour_scale <- function(n) {
  ggplot2::scale_colour_manual(
    values = rep(STBAM_PALETTE, length.out = max(n, 1)),
    name = NULL
  )
}

#' @noRd
provenance_caption <- function(data) {
  parts <- character()
  if ("parameter_set" %in% names(data)) {
    parts <- c(parts, paste0("Parameter set: ",
                             paste(unique(data$parameter_set), collapse = ", ")))
  }
  if ("residue_dt50_days" %in% names(data)) {
    parts <- c(parts, sprintf("Residue DT50 %.4g d; surface-seed DT50 %.4g d",
                              unique(data$residue_dt50_days)[1],
                              unique(data$surface_seed_dt50_days)[1]))
  }
  paste(parts, collapse = "  |  ")
}

#' @noRd
series_label <- function(data, colour_by) {
  if (is.null(colour_by) || !colour_by %in% names(data)) {
    return(factor(rep("All scenarios", nrow(data))))
  }
  factor(as.character(data[[colour_by]]))
}

#' @noRd
timecourse_plot <- function(data, y, title, y_lab, colour_by,
                            log_y = FALSE, threshold = NULL,
                            threshold_label = NULL, subtitle = NULL) {
  if (nrow(data) == 0L) {
    stbam_abort("No data to plot. Widen the scenario selection.")
  }
  data$.series <- series_label(data, colour_by)
  data$.y <- data[[y]]

  p <- ggplot2::ggplot(data, ggplot2::aes(x = .data$day, y = .data$.y,
                                          colour = .data$.series)) +
    ggplot2::geom_line(linewidth = 0.8, na.rm = TRUE)

  if (!is.null(threshold)) {
    p <- p +
      ggplot2::geom_hline(yintercept = threshold, linetype = "dashed",
                          colour = "grey25", linewidth = 0.6) +
      ggplot2::annotate("text", x = max(data$day), y = threshold,
                        label = threshold_label %||% "", hjust = 1.02,
                        vjust = -0.6, size = 3, colour = "grey25")
  }

  p <- p +
    stbam_colour_scale(nlevels(data$.series)) +
    ggplot2::labs(title = wrap_text(title), subtitle = wrap_text(subtitle),
                  x = "Days since sowing", y = y_lab,
                  caption = wrap_text(provenance_caption(data))) +
    theme_stbam() +
    stbam_legend_guide()

  if (log_y) {
    p <- p + ggplot2::scale_y_log10(labels = scales::label_number())
  } else {
    p <- p + ggplot2::scale_y_continuous(labels = scales::label_number())
  }
  p
}

#' Surface seed remaining over time
#'
#' @param timecourse Output of [build_daily_timecourse].
#' @param colour_by Column mapped to colour.
#' @param log_y Use a logarithmic y axis.
#' @return A ggplot.
#' @export
plot_surface_seeds <- function(timecourse, colour_by = "scenario_id",
                               log_y = FALSE) {
  data <- dplyr::distinct(
    timecourse,
    dplyr::across(dplyr::any_of(c("scenario_id", "crop", "rate_level",
                                  "planting_method", "planting_method_label",
                                  "seeding_rate_bound", "seed_mass_bound",
                                  "parameter_set", "residue_dt50_days",
                                  "surface_seed_dt50_days"))),
    .data$day, .data$surface_seeds_per_m2
  )
  timecourse_plot(
    data, "surface_seeds_per_m2",
    title = "Treated seed remaining on the soil surface",
    subtitle = "First-order surface-seed disappearance (displacement, burial, predation)",
    y_lab = expression(Surface~seed~density~(seeds/m^2)),
    colour_by = colour_by, log_y = log_y
  )
}

#' Active ingredient remaining per seed over time
#' @inheritParams plot_surface_seeds
#' @export
plot_ai_per_seed <- function(timecourse, colour_by = "scenario_id",
                             log_y = FALSE) {
  data <- dplyr::distinct(
    timecourse,
    dplyr::across(dplyr::any_of(c("scenario_id", "crop", "rate_level",
                                  "planting_method", "planting_method_label",
                                  "seeding_rate_bound", "seed_mass_bound",
                                  "parameter_set", "residue_dt50_days",
                                  "surface_seed_dt50_days"))),
    .data$day, .data$ai_per_seed_mg
  )
  timecourse_plot(
    data, "ai_per_seed_mg",
    title = "Active ingredient remaining per treated seed",
    subtitle = "First-order residue dissipation on or in the seed",
    y_lab = "Active ingredient (mg a.i./seed)",
    colour_by = colour_by, log_y = log_y
  )
}

#' Active ingredient on the soil surface over time
#'
#' The product of the two independent processes.
#' @inheritParams plot_surface_seeds
#' @export
plot_surface_ai <- function(timecourse, colour_by = "scenario_id",
                            log_y = FALSE) {
  data <- dplyr::distinct(
    timecourse,
    dplyr::across(dplyr::any_of(c("scenario_id", "crop", "rate_level",
                                  "planting_method", "planting_method_label",
                                  "seeding_rate_bound", "seed_mass_bound",
                                  "parameter_set", "residue_dt50_days",
                                  "surface_seed_dt50_days"))),
    .data$day, .data$surface_ai_mg_per_m2
  )
  timecourse_plot(
    data, "surface_ai_mg_per_m2",
    title = "Active ingredient associated with surface seed",
    subtitle = "Product of surface-seed disappearance and residue dissipation",
    y_lab = expression(Surface~loading~(mg~a.i./m^2)),
    colour_by = colour_by, log_y = log_y
  )
}

#' Both dissipation processes on one normalised axis
#'
#' Makes the separation of the two half-lives immediately visible.
#' @param timecourse Output of [build_daily_timecourse].
#' @return A ggplot.
#' @export
plot_process_separation <- function(timecourse) {
  scenario_id <- timecourse$scenario_id[1]
  one <- timecourse[timecourse$scenario_id == scenario_id, ]
  one <- dplyr::distinct(one, .data$day, .data$surface_seeds_per_m2,
                         .data$ai_per_seed_mg, .data$surface_ai_mg_per_m2,
                         .data$residue_dt50_days, .data$surface_seed_dt50_days,
                         .data$parameter_set)
  base <- one[one$day == min(one$day), ]

  long <- rbind(
    data.frame(day = one$day,
               value = one$surface_seeds_per_m2 / base$surface_seeds_per_m2[1],
               process = sprintf("Surface seed remaining (DT50 %.4g d)",
                                 base$surface_seed_dt50_days[1])),
    data.frame(day = one$day,
               value = one$ai_per_seed_mg / base$ai_per_seed_mg[1],
               process = sprintf("Residue per seed (DT50 %.4g d)",
                                 base$residue_dt50_days[1])),
    data.frame(day = one$day,
               value = one$surface_ai_mg_per_m2 / base$surface_ai_mg_per_m2[1],
               process = sprintf("Surface loading, combined (DT50 %.4g d)",
                                 combined_surface_ai_dt50(
                                   base$surface_seed_dt50_days[1],
                                   base$residue_dt50_days[1])))
  )
  long$process <- factor(long$process, levels = unique(long$process))

  ggplot2::ggplot(long, ggplot2::aes(.data$day, .data$value,
                                     colour = .data$process)) +
    ggplot2::geom_line(linewidth = 0.9, na.rm = TRUE) +
    stbam_colour_scale(3) +
    ggplot2::scale_y_continuous(labels = scales::label_percent()) +
    ggplot2::labs(
      title = "Two independent processes, two half-lives",
      subtitle = wrap_text(paste(
        "Surface-seed disappearance and residue dissipation are modelled",
        "separately; the surface loading is their product"
      )),
      x = "Days since sowing", y = "Remaining, relative to sowing",
      caption = paste0("Scenario: ", scenario_id,
                       "  |  Parameter set: ", base$parameter_set[1])
    ) +
    theme_stbam() +
    stbam_legend_guide()
}

#' Dose over time with the effects metric shown
#' @inheritParams plot_surface_seeds
#' @export
plot_dose <- function(timecourse, colour_by = "diet_fraction", log_y = FALSE) {
  metrics <- unique(timecourse$effects_metric)
  threshold <- if (length(metrics) == 1L) metrics else NULL
  label <- if (length(metrics) == 1L) {
    sprintf("Effects metric = %.4g mg a.i./kg bw/d", metrics)
  } else {
    NULL
  }
  data <- timecourse
  if (identical(colour_by, "diet_fraction")) {
    data$diet_fraction <- paste0(
      formatC(data$diet_fraction * 100, format = "g", digits = 3), "% diet"
    )
  }
  timecourse_plot(
    data, "dose_mg_kg_bw_day",
    title = "Estimated daily dose",
    subtitle = "Calculated regulatory exposure; not capped at the feasible dietary fraction",
    y_lab = "Dose (mg a.i./kg bw/day)",
    colour_by = colour_by, log_y = log_y,
    threshold = threshold, threshold_label = label
  )
}

#' Risk quotient over time with the level of concern shown
#' @inheritParams plot_dose
#' @export
plot_risk_quotient <- function(timecourse, colour_by = "diet_fraction",
                               log_y = FALSE) {
  data <- timecourse
  if (identical(colour_by, "diet_fraction")) {
    data$diet_fraction <- paste0(
      formatC(data$diet_fraction * 100, format = "g", digits = 3), "% diet"
    )
  }
  metric_names <- unique(timecourse$metric_id)
  timecourse_plot(
    data, "rq",
    title = "Risk quotient",
    subtitle = paste0("Effects metric: ",
                      paste(metric_names, collapse = ", ")),
    y_lab = "Risk quotient (dose / effects metric)",
    colour_by = colour_by, log_y = log_y,
    threshold = STBAM_DEFAULT_LOC,
    threshold_label = sprintf("RQ = %s", fmt_sig(STBAM_DEFAULT_LOC))
  )
}

#' Exposure feasibility over time
#'
#' Required search area against the maximum search area. Where the required
#' area exceeds the MSA, the modelled dietary fraction is not obtainable.
#' @param timecourse Output of [build_daily_timecourse].
#' @param colour_by Column mapped to colour.
#' @return A ggplot.
#' @export
plot_search_area <- function(timecourse, colour_by = "diet_fraction") {
  data <- timecourse
  msa <- unique(data$msa_m2)
  if (identical(colour_by, "diet_fraction")) {
    data$diet_fraction <- paste0(
      formatC(data$diet_fraction * 100, format = "g", digits = 3), "% diet"
    )
  }
  data$.series <- series_label(data, colour_by)

  p <- ggplot2::ggplot(data, ggplot2::aes(.data$day,
                                          .data$required_search_area_m2,
                                          colour = .data$.series)) +
    ggplot2::geom_line(linewidth = 0.8, na.rm = TRUE) +
    stbam_colour_scale(nlevels(data$.series)) +
    ggplot2::scale_y_log10(labels = scales::label_number()) +
    ggplot2::labs(
      title = "Search area required to obtain the modelled diet",
      subtitle = wrap_text(paste(
        "Above the maximum search area the modelled dietary fraction is not",
        "physically obtainable"
      )),
      x = "Days since sowing",
      y = expression(Required~search~area~(m^2)~-~log~scale),
      caption = wrap_text(provenance_caption(data))
    ) +
    theme_stbam() +
    stbam_legend_guide()

  if (length(msa) == 1L) {
    p <- p +
      ggplot2::geom_hline(yintercept = msa, linetype = "dashed",
                          colour = "grey25", linewidth = 0.6) +
      ggplot2::annotate("text", x = max(data$day), y = msa,
                        label = sprintf("Maximum search area = %g m2", msa),
                        hjust = 1.02, vjust = -0.6, size = 3, colour = "grey25")
  }
  p
}

#' Maximum feasible dietary fraction over time
#' @inheritParams plot_search_area
#' @export
plot_feasible_diet <- function(timecourse, colour_by = "scenario_id") {
  data <- dplyr::distinct(
    timecourse,
    dplyr::across(dplyr::any_of(c("scenario_id", "crop", "rate_level",
                                  "planting_method", "planting_method_label",
                                  "receptor_id", "size_class", "parameter_set",
                                  "residue_dt50_days",
                                  "surface_seed_dt50_days"))),
    .data$day, .data$max_feasible_diet_fraction
  )
  data$.series <- series_label(data, colour_by)

  ggplot2::ggplot(data, ggplot2::aes(.data$day,
                                     .data$max_feasible_diet_fraction,
                                     colour = .data$.series)) +
    ggplot2::geom_line(linewidth = 0.8, na.rm = TRUE) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", colour = "grey25",
                        linewidth = 0.6) +
    ggplot2::annotate("text", x = max(data$day), y = 1,
                      label = "A full daily diet", hjust = 1.02, vjust = -0.6,
                      size = 3, colour = "grey25") +
    stbam_colour_scale(nlevels(data$.series)) +
    ggplot2::scale_y_log10(labels = scales::label_percent()) +
    ggplot2::labs(
      title = "Maximum dietary fraction obtainable within the search area",
      subtitle = "Declines with surface-seed disappearance, not with residue dissipation",
      x = "Days since sowing",
      y = "Obtainable share of the daily diet (log scale)",
      caption = wrap_text(provenance_caption(data))
    ) +
    theme_stbam() +
    stbam_legend_guide()
}

#' Compare peak risk quotient across scenarios
#'
#' @param scenario_summary Output of [build_scenario_summary].
#' @param x Column on the x axis.
#' @param facet Optional faceting column.
#' @return A ggplot.
#' @export
plot_rq_comparison <- function(scenario_summary, x = "crop", facet = "size_class") {
  data <- scenario_summary
  data$.x <- factor(as.character(data[[x]]))
  p <- ggplot2::ggplot(data, ggplot2::aes(.data$.x, .data$peak_rq)) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", colour = "grey25") +
    ggplot2::geom_point(ggplot2::aes(colour = factor(.data$rate_level)),
                        position = ggplot2::position_jitter(width = 0.15,
                                                            height = 0),
                        alpha = 0.75, size = 1.9, na.rm = TRUE) +
    stbam_colour_scale(length(unique(data$rate_level))) +
    ggplot2::scale_y_log10(labels = scales::label_number()) +
    ggplot2::labs(
      title = "Peak risk quotient across scenarios",
      subtitle = "Each point is one agronomic bound combination",
      x = NULL, y = "Peak risk quotient (log scale)",
      caption = wrap_text(provenance_caption(data))
    ) +
    theme_stbam() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  if (!is.null(facet) && facet %in% names(data)) {
    p <- p + ggplot2::facet_wrap(stats::as.formula(paste("~", facet)))
  }
  p
}

#' Compare duration above the level of concern across scenarios
#' @inheritParams plot_rq_comparison
#' @export
plot_duration_comparison <- function(scenario_summary, x = "crop",
                                     facet = "size_class") {
  data <- scenario_summary
  data$.x <- factor(as.character(data[[x]]))
  p <- ggplot2::ggplot(data, ggplot2::aes(.data$.x, .data$days_above_loc)) +
    ggplot2::geom_point(ggplot2::aes(colour = factor(.data$rate_level)),
                        position = ggplot2::position_jitter(width = 0.15,
                                                            height = 0),
                        alpha = 0.75, size = 1.9, na.rm = TRUE) +
    stbam_colour_scale(length(unique(data$rate_level))) +
    ggplot2::labs(
      title = "Duration above the effects metric",
      subtitle = "Days for which the calculated dose remains at or above the metric",
      x = NULL, y = "Days above the effects metric",
      caption = wrap_text(provenance_caption(data))
    ) +
    theme_stbam() +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 45, hjust = 1))
  if (!is.null(facet) && facet %in% names(data)) {
    p <- p + ggplot2::facet_wrap(stats::as.formula(paste("~", facet)))
  }
  p
}

#' Save a plot at publication quality
#'
#' Writes PNG and, where the `svglite` device is available, SVG.
#'
#' @param plot A ggplot.
#' @param path Output path without extension.
#' @param width,height Size in inches.
#' @param dpi Raster resolution.
#' @return The paths written, invisibly.
#' @export
save_plot <- function(plot, path, width = 10, height = 6, dpi = 300) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  written <- character()
  png_path <- paste0(path, ".png")
  ggplot2::ggsave(png_path, plot, width = width, height = height, dpi = dpi,
                  bg = "white")
  written <- c(written, png_path)
  if (requireNamespace("svglite", quietly = TRUE)) {
    svg_path <- paste0(path, ".svg")
    ggplot2::ggsave(svg_path, plot, width = width, height = height,
                    device = svglite::svglite, bg = "white")
    written <- c(written, svg_path)
  }
  invisible(written)
}

