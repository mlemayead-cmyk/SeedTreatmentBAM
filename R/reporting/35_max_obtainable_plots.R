# Maximum-obtainable-exposure figures.
#
# These plots consume canonical daily_timecourse and figure-metadata output
# only -- no scientific calculation lives here (same rule as 30_plots.R).
# The principal figure distinguishes two exposure concepts that must never
# be silently conflated (specification section 10.3-10.4):
#
#   "100% treated-seed diet"      the conditional RQ if the receptor obtained
#                                  its full assumed dietary requirement as
#                                  treated seed, uncapped by availability.
#   "Maximum obtainable within MSA"  the RQ actually achievable, capped at the
#                                  lesser of the food requirement and the
#                                  treated seed available within the
#                                  assessment's own MSA policy.

#' @noRd
validate_plot_slice <- function(timecourse, unique_columns, function_name,
                                metadata_by_receptor = NULL) {
  for (column in unique_columns) {
    if (!column %in% names(timecourse)) {
      stbam_abort(function_name, "() is missing required column `", column,
                  "`.")
    }
    if (length(unique(timecourse[[column]])) != 1L) {
      stbam_abort(function_name, "() requires a single `", column,
                  "`; filter `timecourse` before plotting.")
    }
  }
  if (!is.null(metadata_by_receptor)) {
    missing <- setdiff(unique(timecourse$receptor_id),
                       names(metadata_by_receptor))
    if (length(missing) > 0L) {
      stbam_abort(function_name, "() is missing readable metadata for ",
                  "receptor(s): ", paste(missing, collapse = ", "), ".")
    }
  }
  invisible(TRUE)
}

#' Principal figure: conditional versus maximum-obtainable RQ through time
#'
#' A figure exported from this function must be understandable without
#' Shiny: title, subtitle and caption together state the scenario,
#' receptor, effects metric, fate parameters, MSA basis and RQ/LOC
#' definition (specification section 10.4; see [build_figure_metadata] and
#' [format_figure_footnotes]).
#'
#' @param timecourse Output of [build_daily_timecourse], filtered to ONE
#'   `scenario_id` x `receptor_id` x `metric_id` (all modelled days; the
#'   `diet_fraction == 1` rows are used).
#' @param metadata Output of [build_figure_metadata] for the same row.
#' @param detail `"full"` (self-contained caption, for export/Word/PDF) or
#'   `"concise"` (shorter caption, for on-screen Shiny display next to a
#'   separate "current assumptions" panel).
#' @return A ggplot.
#' @export
plot_max_obtainable_exposure <- function(timecourse, metadata,
                                         detail = c("full", "concise")) {
  detail <- match.arg(detail)
  one <- timecourse[timecourse$diet_fraction == 1, ]
  one <- one[order(one$day), ]
  if (nrow(one) == 0L) {
    stbam_abort("No diet_fraction == 1 rows to plot. Check the scenario ",
                "and receptor selection.")
  }
  # This function's title and subtitle name exactly one scenario, receptor
  # and metric; silently plotting more would produce a figure whose label
  # does not match its data (independent review finding A6).
  for (col in c("scenario_id", "receptor_id", "metric_id")) {
    if (length(unique(one[[col]])) > 1L) {
      stbam_abort("plot_max_obtainable_exposure() requires a single `", col,
                  "`; received ", length(unique(one[[col]])), ". Filter ",
                  "`timecourse` first, or use ",
                  "plot_max_obtainable_small_multiple() for several ",
                  "receptors.")
    }
  }

  long <- rbind(
    data.frame(day = one$day, rq = one$rq,
              series = "100% treated-seed diet"),
    data.frame(day = one$day, rq = one$max_obtainable_rq,
              series = "Maximum obtainable within MSA")
  )
  long$series <- factor(
    long$series,
    levels = c("100% treated-seed diet", "Maximum obtainable within MSA")
  )

  title <- sprintf("Conditional and maximum-obtainable RQ through time — %s",
                   metadata$receptor_label)
  subtitle <- sprintf("%s  |  %s", metadata$scenario_label,
                      metadata$metric_label)

  ggplot2::ggplot(long, ggplot2::aes(.data$day, .data$rq,
                                     colour = .data$series)) +
    ggplot2::geom_line(linewidth = 0.95, na.rm = TRUE) +
    ggplot2::geom_hline(yintercept = metadata$loc, linetype = "dashed",
                        colour = "grey25", linewidth = 0.6) +
    ggplot2::annotate("text", x = max(long$day), y = metadata$loc,
                      label = sprintf("LOC (RQ = %s)", fmt_sig(metadata$loc)),
                      hjust = 1.02, vjust = -0.6, size = 3, colour = "grey25") +
    stbam_colour_scale(2) +
    ggplot2::scale_y_continuous(labels = scales::label_number()) +
    ggplot2::labs(
      title = wrap_text(title), subtitle = wrap_text(subtitle),
      x = "Days since sowing", y = "Risk quotient (dose / effects metric)",
      caption = format_figure_footnotes(metadata, detail = detail)
    ) +
    theme_stbam() +
    stbam_legend_guide()
}

#' Small-multiple maximum-obtainable-exposure figure across receptor sizes
#'
#' One panel per receptor size (typically small/medium/large birds, or
#' small/medium/large mammals), sharing a common x axis. Differences among
#' receptor sizes are the point of this figure, so panels use independent
#' y-axis scales by default -- forcing identical limits across a 20 g and a
#' 1000 g receptor would make the smaller receptor's curve unreadable. This
#' is stated explicitly in the figure's own footnote, never left implicit.
#'
#' @param timecourse Output of [build_daily_timecourse], filtered to ONE
#'   `scenario_id` x `metric_id` and the receptor sizes to compare (same
#'   taxon; all modelled days; `diet_fraction == 1` rows are used).
#' @param metadata_by_receptor A named list of [build_figure_metadata] output,
#'   one per `receptor_id` present in `timecourse`, used to build panel
#'   labels and the shared caption. All entries must share the same crop,
#'   scenario and effects metric.
#' @param free_y If `TRUE` (the default), panels use independent y-axis
#'   scales.
#' @param detail `"full"` or `"concise"`, as in [plot_max_obtainable_exposure].
#' @return A ggplot with one facet per receptor size.
#' @export
plot_max_obtainable_small_multiple <- function(timecourse, metadata_by_receptor,
                                               free_y = TRUE,
                                               detail = c("full", "concise")) {
  detail <- match.arg(detail)
  one <- timecourse[timecourse$diet_fraction == 1, ]
  one <- one[order(one$receptor_id, one$day), ]
  if (nrow(one) == 0L) {
    stbam_abort("No diet_fraction == 1 rows to plot.")
  }
  validate_plot_slice(one, c("scenario_id", "metric_id", "taxon"),
                      "plot_max_obtainable_small_multiple",
                      metadata_by_receptor)

  panel_label <- vapply(one$receptor_id, function(id) {
    md <- metadata_by_receptor[[id]]
    if (is.null(md)) return(id)
    md$receptor_label
  }, character(1))
  one$.panel <- factor(panel_label, levels = unique(panel_label[
    order(one$body_weight_g)
  ]))

  long <- rbind(
    data.frame(day = one$day, .panel = one$.panel, rq = one$rq,
              series = "100% treated-seed diet"),
    data.frame(day = one$day, .panel = one$.panel, rq = one$max_obtainable_rq,
              series = "Maximum obtainable within MSA")
  )
  long$series <- factor(
    long$series,
    levels = c("100% treated-seed diet", "Maximum obtainable within MSA")
  )

  first_meta <- metadata_by_receptor[[one$receptor_id[[1]]]]
  title <- "Conditional and maximum-obtainable RQ through time"
  subtitle <- sprintf("%s  |  %s", first_meta$scenario_label,
                      first_meta$metric_label)
  scale_note <- if (isTRUE(free_y)) {
    "Note: y-axis (risk quotient) scales are independent per panel."
  } else {
    "Note: all panels share the same y-axis (risk quotient) scale."
  }
  caption <- paste(
    format_figure_footnotes(
      first_meta, detail = detail,
      metadata_by_receptor = metadata_by_receptor
    ),
    scale_note,
    sep = "\n"
  )

  ggplot2::ggplot(long, ggplot2::aes(.data$day, .data$rq,
                                     colour = .data$series)) +
    ggplot2::geom_line(linewidth = 0.95, na.rm = TRUE) +
    ggplot2::geom_hline(yintercept = first_meta$loc, linetype = "dashed",
                        colour = "grey25", linewidth = 0.6) +
    ggplot2::facet_wrap(~.panel, scales = if (free_y) "free_y" else "fixed",
                        nrow = 1) +
    stbam_colour_scale(2) +
    ggplot2::scale_y_continuous(labels = scales::label_number()) +
    ggplot2::labs(
      title = wrap_text(title), subtitle = wrap_text(subtitle),
      x = "Days since sowing", y = "Risk quotient (dose / effects metric)",
      caption = caption
    ) +
    theme_stbam() +
    stbam_legend_guide()
}

#' Companion diagnostic: seeds available within MSA versus seeds required
#'
#' Shows directly why and when the maximum-obtainable curve diverges from
#' the conditional curve: the divergence point in
#' [plot_max_obtainable_exposure] is exactly where these two lines cross.
#'
#' @param timecourse Output of [build_daily_timecourse], filtered to ONE
#'   `scenario_id` x `receptor_id` x `metric_id` (all modelled days;
#'   `diet_fraction == 1` rows are used).
#' @param metadata Output of [build_figure_metadata] for the same row.
#' @return A ggplot.
#' @export
plot_seed_availability_vs_requirement <- function(timecourse, metadata) {
  one <- timecourse[timecourse$diet_fraction == 1, ]
  one <- one[order(one$day), ]
  if (nrow(one) == 0L) {
    stbam_abort("No diet_fraction == 1 rows to plot.")
  }
  validate_plot_slice(one, c("scenario_id", "receptor_id", "metric_id"),
                      "plot_seed_availability_vs_requirement")

  long <- rbind(
    data.frame(day = one$day, seeds = one$max_obtainable_seeds_within_msa,
              series = sprintf("Treated seed available within %s m2 (%s-term) MSA",
                               fmt_sig(metadata$msa_m2), metadata$msa_term)),
    data.frame(day = one$day, seeds = one$seeds_required_per_day,
              series = "Seeds required for a 100% treated-seed diet")
  )

  ggplot2::ggplot(long, ggplot2::aes(.data$day, .data$seeds,
                                     colour = .data$series)) +
    ggplot2::geom_line(linewidth = 0.9, na.rm = TRUE) +
    stbam_colour_scale(2) +
    ggplot2::scale_y_log10(labels = scales::label_number()) +
    ggplot2::labs(
      title = "Seed availability versus dietary requirement",
      subtitle = wrap_text(paste(
        "Where the availability line crosses below the requirement line,",
        "the maximum-obtainable exposure becomes seed-limited"
      )),
      x = "Days since sowing", y = "Seeds/day — log scale",
      caption = wrap_text(sprintf(
        "%s  |  %s  |  Surface-seed disappearance DT50 = %s d",
        metadata$scenario_label, metadata$receptor_label,
        fmt_sig(metadata$surface_seed_dt50_days)
      ))
    ) +
    theme_stbam() +
    stbam_legend_guide()
}

#' Four-panel process explanation for maximum-obtainable exposure
#'
#' The first three panels separate the two fate processes and their product.
#' The fourth shows, for every supplied receptor, the ratio of treated seed
#' available within the applicable MSA to seed required for a 100% diet. A
#' ratio below one is the point at which maximum-obtainable exposure becomes
#' seed-limited.
#'
#' @param timecourse Output of [build_daily_timecourse], filtered to one
#'   scenario and one effects metric, with all receptor sizes to compare.
#' @param metadata_by_receptor Named list of [build_figure_metadata] objects.
#' @param detail `"full"` or `"concise"`.
#' @return A faceted ggplot.
#' @export
plot_exposure_processes <- function(timecourse, metadata_by_receptor,
                                    detail = c("full", "concise")) {
  detail <- match.arg(detail)
  one <- timecourse[timecourse$diet_fraction == 1, ]
  if (nrow(one) == 0L) {
    stbam_abort("No diet_fraction == 1 rows to plot.")
  }
  validate_plot_slice(one, c("scenario_id", "metric_id", "taxon"),
                      "plot_exposure_processes", metadata_by_receptor)
  one <- one[order(one$receptor_id, one$day), ]
  first_id <- one$receptor_id[[1]]
  process <- one[one$receptor_id == first_id, ]
  process <- process[!duplicated(process$day), ]
  surface_only <- identical(process$accessible_pool_basis[[1]],
                            "SURFACE_SEED_ONLY")
  seed_values <- if (surface_only) {
    process$surface_seeds_per_m2
  } else {
    process$accessible_seeds_per_m2_t
  }
  accessible_ai_values <- seed_values * process$ai_per_seed_mg

  panel_levels <- c(
    if (surface_only) "A. Surface seeds remaining\n(seeds/m2)" else
      "A. Accessible seeds remaining\n(seeds/m2; surface + buried)",
    "B. Residue remaining per seed\n(mg a.i./seed)",
    if (surface_only) "C. Active ingredient with surface seed\n(mg a.i./m2)" else
      "C. Active ingredient with accessible seed\n(mg a.i./m2)",
    "D. Exposure feasibility\n(available / required seeds)"
  )
  process_data <- rbind(
    data.frame(day = process$day, value = seed_values,
               panel = panel_levels[[1]], series = "Scenario process"),
    data.frame(day = process$day, value = process$ai_per_seed_mg,
               panel = panel_levels[[2]], series = "Scenario process"),
    data.frame(day = process$day, value = accessible_ai_values,
               panel = panel_levels[[3]], series = "Scenario process")
  )

  receptor_label <- vapply(one$receptor_id, function(id) {
    md <- metadata_by_receptor[[id]]
    if (is.null(md)) id else md$receptor_label
  }, character(1))
  feasibility <- data.frame(
    day = one$day,
    value = one$max_obtainable_diet_fraction,
    panel = panel_levels[[4]],
    series = receptor_label
  )
  long <- rbind(process_data, feasibility)
  long$panel <- factor(long$panel, levels = panel_levels)
  long$series <- factor(long$series, levels = unique(long$series))

  first_meta <- metadata_by_receptor[[first_id]]
  threshold <- data.frame(panel = factor(panel_levels[[4]], levels = panel_levels),
                          yintercept = 1)
  caption <- paste(
    format_figure_footnotes(
      first_meta, detail = detail,
      metadata_by_receptor = metadata_by_receptor
    ),
    paste(
      "Panels use independent y-axis scales. Panel D is available / required",
      "treated seeds: 1.0 means enough treated seed is present within the",
      "applicable MSA for a 100% treated-seed diet; values below 1.0 are",
      "seed-limited."
    ),
    sep = "\n"
  )

  ggplot2::ggplot(long, ggplot2::aes(.data$day, .data$value,
                                     colour = .data$series)) +
    ggplot2::geom_line(linewidth = 0.9, na.rm = TRUE) +
    ggplot2::geom_hline(
      data = threshold, ggplot2::aes(yintercept = .data$yintercept),
      inherit.aes = FALSE, linetype = "dashed", colour = "grey25",
      linewidth = 0.6
    ) +
    ggplot2::facet_wrap(~panel, scales = "free_y", ncol = 2) +
    stbam_colour_scale(nlevels(long$series)) +
    ggplot2::scale_y_continuous(labels = scales::label_number()) +
    ggplot2::labs(
      title = "Processes controlling maximum-obtainable exposure",
      subtitle = wrap_text(first_meta$scenario_label),
      x = "Days since sowing", y = NULL, caption = caption
    ) +
    theme_stbam() +
    stbam_legend_guide()
}

#' RQ through time under assumed treated-seed dietary fractions
#'
#' This preserves the model's conventional dietary-fraction view while making
#' explicit that the fractions are assumptions, not demonstrations of physical
#' obtainability. These curves decline with residue dissipation per seed; the
#' separate maximum-obtainable figure evaluates surface-seed availability.
#'
#' @param timecourse Output of [build_daily_timecourse], filtered to one
#'   scenario, receptor and effects metric.
#' @param metadata Output of [build_figure_metadata].
#' @param detail `"full"` or `"concise"`.
#' @return A ggplot.
#' @export
plot_dietary_fraction_rq <- function(timecourse, metadata,
                                     detail = c("full", "concise")) {
  detail <- match.arg(detail)
  if (nrow(timecourse) == 0L) stbam_abort("No data to plot.")
  validate_plot_slice(timecourse,
                      c("scenario_id", "receptor_id", "metric_id"),
                      "plot_dietary_fraction_rq")
  data <- timecourse[order(timecourse$diet_fraction, timecourse$day), ]
  data$.diet <- factor(
    paste0(formatC(data$diet_fraction * 100, format = "fg", digits = 3), "%"),
    levels = paste0(formatC(sort(unique(data$diet_fraction)) * 100,
                            format = "fg", digits = 3), "%")
  )
  note <- paste(
    "Dietary fractions are assumed, not demonstrated obtainable. Curve",
    "decline is driven by residue dissipation per seed; consult the",
    "maximum-obtainable figure for MSA-constrained availability."
  )
  caption <- paste(format_figure_footnotes(metadata, detail = detail), note,
                   sep = "\n")

  ggplot2::ggplot(data, ggplot2::aes(.data$day, .data$rq,
                                     colour = .data$.diet)) +
    ggplot2::geom_line(linewidth = 0.85, na.rm = TRUE) +
    ggplot2::geom_hline(yintercept = metadata$loc, linetype = "dashed",
                        colour = "grey25", linewidth = 0.6) +
    stbam_colour_scale(nlevels(data$.diet)) +
    ggplot2::scale_y_continuous(labels = scales::label_number()) +
    ggplot2::labs(
      title = "RQ through time under assumed treated-seed dietary fractions",
      subtitle = wrap_text(sprintf("%s | %s | %s", metadata$scenario_label,
                                   metadata$receptor_label,
                                   metadata$metric_label)),
      x = "Days since sowing", y = "Risk quotient (dose / effects metric)",
      colour = "Treated-seed diet", caption = caption
    ) +
    theme_stbam() +
    stbam_legend_guide(rows = 1)
}

#' Small-multiple dietary-fraction RQ figure across receptor sizes
#'
#' @param timecourse Output of [build_daily_timecourse], filtered to one
#'   scenario and one effects metric, with all receptor sizes to compare.
#' @param metadata_by_receptor Named list of [build_figure_metadata] objects.
#' @param free_y Whether receptor panels use independent RQ scales.
#' @param detail `"full"` or `"concise"`.
#' @return A faceted ggplot.
#' @export
plot_dietary_fraction_small_multiple <- function(
    timecourse, metadata_by_receptor, free_y = TRUE,
    detail = c("full", "concise")) {
  detail <- match.arg(detail)
  if (nrow(timecourse) == 0L) stbam_abort("No data to plot.")
  validate_plot_slice(timecourse, c("scenario_id", "metric_id", "taxon"),
                      "plot_dietary_fraction_small_multiple",
                      metadata_by_receptor)
  data <- timecourse[order(timecourse$receptor_id, timecourse$diet_fraction,
                           timecourse$day), ]
  data$.panel <- factor(vapply(data$receptor_id, function(id) {
    md <- metadata_by_receptor[[id]]
    if (is.null(md)) id else md$receptor_label
  }, character(1)), levels = unique(vapply(
    metadata_by_receptor, function(x) x$receptor_label, character(1)
  )))
  fractions <- sort(unique(data$diet_fraction))
  fraction_levels <- paste0(formatC(fractions * 100, format = "fg", digits = 3),
                            "%")
  data$.diet <- factor(
    paste0(formatC(data$diet_fraction * 100, format = "fg", digits = 3), "%"),
    levels = fraction_levels
  )
  first_meta <- metadata_by_receptor[[data$receptor_id[[1]]]]
  scale_note <- if (isTRUE(free_y)) {
    "Receptor panels use independent RQ scales."
  } else {
    "All receptor panels use a common RQ scale."
  }
  note <- paste(
    "Dietary fractions are assumed, not demonstrated obtainable. Curve",
    "decline is driven by residue dissipation per seed; consult the",
    "maximum-obtainable figure for MSA-constrained availability."
  )
  caption <- paste(
    format_figure_footnotes(
      first_meta, detail = detail,
      metadata_by_receptor = metadata_by_receptor
    ),
    note, scale_note, sep = "\n"
  )

  ggplot2::ggplot(data, ggplot2::aes(.data$day, .data$rq,
                                     colour = .data$.diet)) +
    ggplot2::geom_line(linewidth = 0.8, na.rm = TRUE) +
    ggplot2::geom_hline(yintercept = first_meta$loc, linetype = "dashed",
                        colour = "grey25", linewidth = 0.6) +
    ggplot2::facet_wrap(~.panel, scales = if (free_y) "free_y" else "fixed",
                        nrow = 1) +
    stbam_colour_scale(nlevels(data$.diet)) +
    ggplot2::scale_y_continuous(labels = scales::label_number()) +
    ggplot2::labs(
      title = "RQ through time under assumed treated-seed dietary fractions",
      subtitle = wrap_text(sprintf("%s | %s", first_meta$scenario_label,
                                   first_meta$metric_label)),
      x = "Days since sowing", y = "Risk quotient (dose / effects metric)",
      caption = caption
    ) +
    theme_stbam() +
    stbam_legend_guide(rows = 1)
}
