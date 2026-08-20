"""Extract canonical reference data from the source calculation workbooks.

This script is the ONLY bridge between the immutable source workbooks and the
R model.  It reads the workbook package statically (no Excel, no COM, no
LibreOffice, no VBA execution, no formula engine) and writes plain CSV
reference tables into ``data/reference``.

The source workbooks are treated as read-only evidence.  The script records a
SHA-256 for every workbook it reads, before and after, and refuses to continue
if a hash changes.

Run from the project root:

    python scripts/extract_reference_data.py

Outputs (all in data/reference):
    source_manifest.csv             workbook hashes and extraction timestamp
    crop_seeding_parameters.csv     per-crop agronomy (TKW, seeding rates, methods)
    planting_method_parameters.csv  surface-seed fractions by planting method
    receptor_parameters.csv         body weight, FIR model, MSA, accessibility
    fir_regressions.csv             full Nagy food-intake regression library
    effects_metrics.csv             screening and refined-additional metrics
    dissipation_parameters.csv      residue and surface-seed DT50s
    scenario_definitions.csv        crop x application-rate scenarios per workbook
"""

from __future__ import annotations

import csv
import hashlib
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from workbook_static import StaticWorkbook  # noqa: E402

PROJECT_ROOT = Path(__file__).resolve().parent.parent
REFERENCE_DIR = PROJECT_ROOT / "data" / "reference"

# The review workspace holds the immutable source workbooks.  Only this constant
# needs to change if the evidence workspace moves.
SOURCE_WORKSPACE = Path(
    r"c:\MonDossierMartin\Python_Local\Python_Document analysis"
)
WORKBOOK_DIR = SOURCE_WORKSPACE / "Documents"

# The Small Cereals workbook is the audited reference case (Phase 3A, 1,115
# independent numeric checks).  It is the authority for shared assumption
# sheets.  The other workbooks contribute their own crop/rate scenarios.
PRIMARY_WORKBOOK = (
    WORKBOOK_DIR
    / "Calculation Workbooks"
    / "THE 1 small cereals Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026.xlsm"
)

SECONDARY_WORKBOOKS = {
    "small_cereals_msa": WORKBOOK_DIR
    / "THE 1b small cereals Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm",
    "canola": WORKBOOK_DIR
    / "THE 2 canola rapeseed mustard Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm",
    "legumes_deep": WORKBOOK_DIR
    / "Calculation Workbooks"
    / "THE 3 deep legumes Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm",
    "legumes_shallow": WORKBOOK_DIR
    / "Calculation Workbooks"
    / "THE 3 shallow legumes Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm",
    "cucurbits": WORKBOOK_DIR
    / "Calculation Workbooks"
    / "THE 5 cucurbits Bird and Mammal Seed Treatment RA Workbook 2026 for QAQC 08MAY2026 MSA doses.xlsm",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def number(text: str) -> float | None:
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def flag(text: str) -> str:
    return "TRUE" if (text or "").strip().upper() == "Y" else "FALSE"


def write_csv(name: str, header: list[str], rows: list[list]) -> Path:
    path = REFERENCE_DIR / name
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)
    print(f"  {name:<34} {len(rows):>4} rows")
    return path


# ---------------------------------------------------------------------------
# Seeding Assumptions -> crop_seeding_parameters.csv
# ---------------------------------------------------------------------------

def extract_crop_seeding(wb: StaticWorkbook) -> list[list]:
    """Per-crop agronomic parameters.

    The workbook resolves a lower and an upper bound on seeds/ha as:

        lower seeds/ha = D if supplied, else K
        upper seeds/ha = E if supplied, else L

    where D/E are directly supplied seed counts and K/L are conversions from
    the mass-based seeding rate.  K uses the *high* seed weight (fewest seeds
    per kg) and L uses the *low* seed weight (most seeds per kg), so the pair
    brackets the plausible seed count.  This asymmetry is deliberate and is
    reproduced exactly by the R engine.
    """
    rows = []
    cells = wb.cells["Seeding Assumptions"]
    max_row = max(int(ref.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) for ref in cells)
    for row in range(2, max_row + 1):
        crop = wb.value("Seeding Assumptions", f"A{row}").strip()
        if not crop:
            continue
        tkw_low = number(wb.value("Seeding Assumptions", f"B{row}"))
        tkw_high = number(wb.value("Seeding Assumptions", f"C{row}"))
        direct_low = number(wb.value("Seeding Assumptions", f"D{row}"))
        direct_high = number(wb.value("Seeding Assumptions", f"E{row}"))
        converted_low_hsw = number(wb.value("Seeding Assumptions", f"K{row}"))
        converted_high_lsw = number(wb.value("Seeding Assumptions", f"L{row}"))

        seeds_ha_low = direct_low if direct_low is not None else converted_low_hsw
        seeds_ha_high = direct_high if direct_high is not None else converted_high_lsw

        rows.append([
            crop,
            tkw_low, tkw_high,
            direct_low if direct_low is not None else "",
            direct_high if direct_high is not None else "",
            number(wb.value("Seeding Assumptions", f"F{row}")),  # kg/ha low rate, low TKW
            number(wb.value("Seeding Assumptions", f"G{row}")),  # kg/ha low rate, high TKW
            number(wb.value("Seeding Assumptions", f"H{row}")),  # kg/ha high rate, low TKW
            number(wb.value("Seeding Assumptions", f"I{row}")),  # kg/ha high rate, high TKW
            seeds_ha_low if seeds_ha_low is not None else "",
            seeds_ha_high if seeds_ha_high is not None else "",
            "DIRECT" if direct_low is not None else "CONVERTED_FROM_MASS",
            "DIRECT" if direct_high is not None else "CONVERTED_FROM_MASS",
            flag(wb.value("Seeding Assumptions", f"N{row}")),
            flag(wb.value("Seeding Assumptions", f"O{row}")),
            flag(wb.value("Seeding Assumptions", f"P{row}")),
            flag(wb.value("Seeding Assumptions", f"Q{row}")),
            flag(wb.value("Seeding Assumptions", f"R{row}")),
            wb.value("Seeding Assumptions", f"S{row}").strip(),
            "ASSESSMENT_DEFAULT",
        ])
    return rows


CROP_SEEDING_HEADER = [
    "crop", "tkw_low_g_per_1000", "tkw_high_g_per_1000",
    "seeding_rate_low_seeds_per_ha_direct", "seeding_rate_high_seeds_per_ha_direct",
    "seeding_rate_low_kg_per_ha_low_tkw", "seeding_rate_low_kg_per_ha_high_tkw",
    "seeding_rate_high_kg_per_ha_low_tkw", "seeding_rate_high_kg_per_ha_high_tkw",
    "seeds_per_ha_low", "seeds_per_ha_high",
    "seeds_per_ha_low_basis", "seeds_per_ha_high_basis",
    "spring_seeded", "fall_seeded", "broadcast_seeded",
    "drill_seeded", "precision_planted",
    "source", "status",
]


# ---------------------------------------------------------------------------
# General Look ups -> planting_method_parameters.csv
# ---------------------------------------------------------------------------

def extract_planting_methods(wb: StaticWorkbook) -> list[list]:
    rows = []
    for row in range(2, 6):
        method = wb.value("General Look ups", f"F{row}").strip()
        if not method:
            continue
        rows.append([
            method,
            {
                "Spring - standard drill": "drill_spring",
                "Fall - standard drill": "drill_fall",
                "Precision planter": "precision",
                "Broadcast": "broadcast",
            }.get(method, method.lower().replace(" ", "_")),
            number(wb.value("General Look ups", f"G{row}")),
            wb.value("General Look ups", f"H{row}").strip(),
            "ASSESSMENT_DEFAULT",
        ])
    return rows


PLANTING_METHOD_HEADER = [
    "planting_method_label", "planting_method", "surface_seed_fraction",
    "source", "status",
]


# ---------------------------------------------------------------------------
# FIR Assumptions + Further Risk Characterization -> receptor_parameters.csv
# ---------------------------------------------------------------------------

SIZE_CLASS_BY_ROW = {
    3: ("bird", "small"), 4: ("bird", "medium"), 5: ("bird", "large"),
    6: ("mammal", "small"), 7: ("mammal", "medium"), 8: ("mammal", "large"),
}


def extract_receptors(wb: StaticWorkbook) -> list[list]:
    """Receptor parameters.

    Body weight, food-intake regression and food-intake rate come from the
    veryHidden 'FIR Assumptions' sheet.  Maximum search areas and the
    surface-only accessibility switch come from 'Further Risk
    Characterization' rows 11-13 (birds in columns B-E, mammals in G-J).
    """
    frc_rows = {"bird": [11, 12, 13], "mammal": [11, 12, 13]}
    frc_cols = {"bird": ("B", "C", "D", "E"), "mammal": ("G", "H", "I", "J")}

    rows = []
    for sheet_row, (taxon, size_class) in SIZE_CLASS_BY_ROW.items():
        body_weight = number(wb.value("FIR Assumptions", f"B{sheet_row}"))
        index = {"small": 0, "medium": 1, "large": 2}[size_class]
        frc_row = frc_rows[taxon][index]
        bw_col, short_col, long_col, surface_col = frc_cols[taxon]

        frc_bw = number(wb.value("Further Risk Characterization", f"{bw_col}{frc_row}"))
        if frc_bw is not None and body_weight is not None and abs(frc_bw - body_weight) > 1e-9:
            raise ValueError(
                f"Body weight mismatch for {taxon}/{size_class}: "
                f"FIR Assumptions {body_weight} vs FRC {frc_bw}"
            )

        rows.append([
            f"{taxon}_{size_class}",
            taxon,
            size_class,
            body_weight,
            wb.value("FIR Assumptions", f"C{sheet_row}").strip(),
            number(wb.value("FIR Assumptions", f"D{sheet_row}")),
            number(wb.value("FIR Assumptions", f"E{sheet_row}")),
            number(wb.value("FIR Assumptions", f"F{sheet_row}")),
            number(wb.value("Further Risk Characterization", f"{short_col}{frc_row}")),
            number(wb.value("Further Risk Characterization", f"{long_col}{frc_row}")),
            flag(wb.value("Further Risk Characterization", f"{surface_col}{frc_row}")),
            "Workbook 'FIR Assumptions' and 'Further Risk Characterization' sheets",
            "ASSESSMENT_DEFAULT",
        ])
    return rows


RECEPTOR_HEADER = [
    "receptor_id", "taxon", "size_class", "body_weight_g",
    "fir_regression_name", "fir_coefficient_a", "fir_exponent_b",
    "food_intake_g_dw_per_day",
    "msa_short_term_m2", "msa_long_term_m2",
    "surface_seed_only", "source", "status",
]


# ---------------------------------------------------------------------------
# FIR Bird/Mammal Regressions -> fir_regressions.csv
# ---------------------------------------------------------------------------

def extract_fir_regressions(wb: StaticWorkbook) -> list[list]:
    rows = []
    for sheet, taxon in (("FIR Bird Regressions", "bird"),
                         ("FIR Mammal Regressions", "mammal")):
        seen = set()
        for row in range(3, 40):
            name = wb.value(sheet, f"D{row}").strip()
            coefficient = number(wb.value(sheet, f"N{row}"))
            exponent = number(wb.value(sheet, f"O{row}"))
            if not name or coefficient is None or exponent is None:
                continue
            key = (name, round(coefficient, 12), round(exponent, 12))
            if key in seen:
                continue
            seen.add(key)
            rows.append([
                taxon, name,
                wb.value(sheet, f"A{row}").strip(),
                wb.value(sheet, f"B{row}").strip(),
                wb.value(sheet, f"C{row}").strip(),
                wb.value(sheet, f"E{row}").strip(),
                coefficient, exponent,
                number(wb.value(sheet, f"K{row}")),
                "ASSESSMENT_REFERENCE",
            ])
    return rows


FIR_REGRESSION_HEADER = [
    "taxon", "regression_name", "reference", "regression_taxon_group",
    "feeding_guild", "diet_assumption",
    "coefficient_a", "exponent_b", "n_species", "status",
]


# ---------------------------------------------------------------------------
# Ecotox Inputs + Further Risk Characterization -> effects_metrics.csv
# ---------------------------------------------------------------------------

def extract_effects_metrics(wb: StaticWorkbook) -> list[list]:
    """Screening and refined-additional effects metrics.

    Documented workflow-stage distinction (reviewer-confirmed; review-workspace
    records TRC-002, CON-001, CLR-001 and WB-LOG-001 are all closed as
    NO_ISSUE / REVIEWER_CLARIFICATION):

      * mammalian CHRONIC SCREENING uses 1.8 mg a.i./kg bw/d (assessment
        Table 1 / register METRIC-004);
      * mammalian CHRONIC FURTHER/REFINED characterization uses 2.4 mg
        a.i./kg bw/d (register METRIC-018).

    The supplied workbook has advanced to the refined stage, so its 'Ecotox
    Inputs for Screening' sheet already carries 2.4.  Emitting that value as
    the screening metric would silently collapse two intentionally distinct
    workflow stages, so the mammal chronic row read from the workbook is
    labelled REFINED and the 1.8 screening metric is added explicitly from the
    assessment register.  Both rows are retained; neither overwrites the other.
    """
    rows = []
    screening = [
        (5, "bird", "acute"), (6, "bird", "chronic"),
        (7, "mammal", "acute"), (8, "mammal", "chronic"),
    ]
    for row, taxon, duration in screening:
        endpoint = number(wb.value("Ecotox Inputs for Screening", f"E{row}"))
        factor = number(wb.value("Ecotox Inputs for Screening", f"H{row}")) or 1.0
        metric = number(wb.value("Ecotox Inputs for Screening", f"I{row}"))

        stage_is_refined = (taxon, duration) == ("mammal", "chronic")
        role = "REFINED" if stage_is_refined else "SCREENING"
        suffix = "refined" if stage_is_refined else "screening"

        rows.append([
            f"{taxon}_{duration}_{suffix}",
            wb.value("Ecotox Inputs for Screening", "C2").strip() or "thiamethoxam",
            taxon, duration, role,
            wb.value("Ecotox Inputs for Screening", f"G{row}").strip(),
            endpoint, factor, metric, "mg a.i./kg bw/d",
            wb.value("Ecotox Inputs for Screening", f"F{row}").strip(),
            "ASSESSMENT_DEFAULT",
        ])

    # Explicit screening-stage mammalian chronic metric (see docstring).
    rows.append([
        "mammal_chronic_screening",
        "thiamethoxam", "mammal", "chronic", "SCREENING",
        "Rat (Tif:RAlf) F2 female offspring NOEL for body weight and body-weight "
        "gain, expressed as a parental male daily-dose estimate",
        1.8, 1.0, 1.8, "mg a.i./kg bw/d",
        "Assessment Table 1 (PMRA#1178124); review register METRIC-004; "
        "reviewer-confirmed screening-stage value",
        "ASSESSMENT_DEFAULT",
    ])

    additional = [
        ("bird", "acute", ("C", "E", "F"), (18, 19, 20)),
        ("bird", "chronic", ("C", "E", "F"), (24, 25, 26)),
        ("mammal", "acute", ("I", "K", "L"), (18, 19, 20)),
        ("mammal", "chronic", ("I", "K", "L"), (24, 25, 26)),
    ]
    for taxon, duration, (index_col, value_col, label_col), sheet_rows in additional:
        for position, row in enumerate(sheet_rows, start=1):
            value = number(wb.value("Further Risk Characterization", f"{value_col}{row}"))
            if value is None:
                continue
            rows.append([
                f"{taxon}_{duration}_additional_{position}",
                "thiamethoxam", taxon, duration, "REFINED_ADDITIONAL",
                wb.value("Further Risk Characterization", f"{label_col}{row}").strip(),
                value, 1.0, value, "mg a.i./kg bw/d",
                "Workbook 'Further Risk Characterization' additional effects metrics",
                "ASSESSMENT_DEFAULT",
            ])
    return rows


EFFECTS_METRIC_HEADER = [
    "metric_id", "active_ingredient", "taxon", "duration_class", "metric_role",
    "endpoint_description", "endpoint_value", "uncertainty_factor",
    "effects_metric", "unit", "source", "status",
]


# ---------------------------------------------------------------------------
# Further Risk Characterization -> dissipation_parameters.csv
# ---------------------------------------------------------------------------

def extract_dissipation(wb: StaticWorkbook) -> list[list]:
    return [
        [
            "residue_dt50_days",
            number(wb.value("Further Risk Characterization", "E4")),
            "days",
            "Single first-order DT50 for thiamethoxam residues on/in treated seed",
            "Workbook 'Further Risk Characterization'!E4; assessment MAIN-P000138",
            "ASSESSMENT_DEFAULT",
        ],
        [
            "surface_seed_dt50_days",
            number(wb.value("Further Risk Characterization", "J4")),
            "days",
            "Single first-order DT50 for loss of treated seed from the soil surface",
            "Workbook 'Further Risk Characterization'!J4; assessment MAIN-P000183",
            "ASSESSMENT_DEFAULT",
        ],
    ]


DISSIPATION_HEADER = ["parameter", "value", "unit", "description", "source", "status"]


# ---------------------------------------------------------------------------
# Seed Inputs and EECs -> scenario_definitions.csv
# ---------------------------------------------------------------------------

def extract_scenarios(wb: StaticWorkbook, workbook_key: str) -> list[list]:
    rows = []
    for row in range(4, 56):
        crop = wb.value("Seed Inputs and EECs", f"B{row}").strip()
        if not crop:
            continue
        units = wb.value("Seed Inputs and EECs", f"F{row}").strip()
        source = wb.value("Seed Inputs and EECs", f"H{row}").strip()
        for level, column in (("high", "C"), ("mid", "D"), ("low", "E")):
            rate = number(wb.value("Seed Inputs and EECs", f"{column}{row}"))
            if rate is None:
                continue
            rows.append([
                workbook_key,
                number(wb.value("Seed Inputs and EECs", f"A{row}")),
                crop, level, rate, units, source, "ASSESSMENT_DEFAULT",
            ])
    return rows


SCENARIO_HEADER = [
    "workbook", "seed_use_number", "crop", "rate_level",
    "application_rate", "application_rate_unit", "source", "status",
]


# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Review-workspace registers copied in with provenance
# ---------------------------------------------------------------------------

# These are curated review outputs, not workbook extracts. They are copied
# verbatim so the R project is self-contained, and hashed so any drift from the
# review workspace is detectable.
COPIED_REGISTERS = {
    "table162_decision_matrix.csv": SOURCE_WORKSPACE / "03_registers" / "table162_decision_matrix.csv",
    "table162_considerations.csv": SOURCE_WORKSPACE / "03_registers" / "table162_considerations.csv",
    "review_core_assumptions.csv": SOURCE_WORKSPACE / "03_registers" / "core_assumptions.csv",
    "review_effects_metrics.csv": SOURCE_WORKSPACE / "03_registers" / "effects_metrics.csv",
}

FIXTURES = {
    "bird_small_cereals_calculation_checks.csv":
        SOURCE_WORKSPACE / "04_review" / "bird_small_cereals_calculation_checks.csv",
}


def copy_with_provenance(mapping: dict[str, Path], destination: Path) -> list[list]:
    destination.mkdir(parents=True, exist_ok=True)
    manifest_rows = []
    for name, path in mapping.items():
        if not path.exists():
            print(f"  WARNING: not found, skipped: {path}", file=sys.stderr)
            continue
        target = destination / name
        target.write_bytes(path.read_bytes())
        manifest_rows.append([name, str(path), sha256(path)])
        print(f"  {name:<44} copied")
    return manifest_rows


def main() -> int:
    REFERENCE_DIR.mkdir(parents=True, exist_ok=True)

    workbooks = {"small_cereals": PRIMARY_WORKBOOK, **SECONDARY_WORKBOOKS}
    missing = [key for key, path in workbooks.items() if not path.exists()]
    if missing:
        print(f"ERROR: workbooks not found: {', '.join(missing)}", file=sys.stderr)
        return 1

    hashes_before = {key: sha256(path) for key, path in workbooks.items()}
    timestamp = datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")

    print(f"Extracting reference data at {timestamp}")
    print(f"Primary (audited) workbook: {PRIMARY_WORKBOOK.name}")

    shared_sheets = {
        "Seeding Assumptions", "General Look ups", "FIR Assumptions",
        "FIR Bird Regressions", "FIR Mammal Regressions",
        "Ecotox Inputs for Screening", "Further Risk Characterization",
        "Seed Inputs and EECs",
    }
    primary = StaticWorkbook(PRIMARY_WORKBOOK, selected_sheets=shared_sheets)

    print("\nShared assumption tables (from the audited Small Cereals workbook):")
    write_csv("crop_seeding_parameters.csv", CROP_SEEDING_HEADER,
              extract_crop_seeding(primary))
    write_csv("planting_method_parameters.csv", PLANTING_METHOD_HEADER,
              extract_planting_methods(primary))
    write_csv("receptor_parameters.csv", RECEPTOR_HEADER,
              extract_receptors(primary))
    write_csv("fir_regressions.csv", FIR_REGRESSION_HEADER,
              extract_fir_regressions(primary))
    write_csv("effects_metrics.csv", EFFECTS_METRIC_HEADER,
              extract_effects_metrics(primary))
    write_csv("dissipation_parameters.csv", DISSIPATION_HEADER,
              extract_dissipation(primary))

    print("\nScenario definitions (from every supplied workbook):")
    scenarios = extract_scenarios(primary, "small_cereals")
    for key, path in SECONDARY_WORKBOOKS.items():
        other = StaticWorkbook(path, selected_sheets={"Seed Inputs and EECs"})
        scenarios.extend(extract_scenarios(other, key))
    write_csv("scenario_definitions.csv", SCENARIO_HEADER, scenarios)

    print("\nReview registers copied into data/reference:")
    register_rows = copy_with_provenance(COPIED_REGISTERS, REFERENCE_DIR)

    print("\nRegression fixtures copied into inst/fixtures:")
    fixture_rows = copy_with_provenance(
        FIXTURES, PROJECT_ROOT / "inst" / "fixtures"
    )

    write_csv(
        "copied_register_manifest.csv",
        ["file_name", "source_path", "sha256"],
        register_rows + fixture_rows,
    )

    hashes_after = {key: sha256(path) for key, path in workbooks.items()}
    changed = [key for key in workbooks if hashes_before[key] != hashes_after[key]]
    if changed:
        print(f"ERROR: source workbook changed during extraction: {changed}",
              file=sys.stderr)
        return 1

    print("\nSource manifest:")
    write_csv(
        "source_manifest.csv",
        ["workbook_key", "file_name", "sha256", "role", "extracted_at"],
        [
            [
                key, workbooks[key].name, hashes_after[key],
                "PRIMARY_AUDITED_REFERENCE" if key == "small_cereals" else "SCENARIO_SOURCE",
                timestamp,
            ]
            for key in workbooks
        ],
    )
    print("\nAll source workbook hashes unchanged. Extraction complete.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
