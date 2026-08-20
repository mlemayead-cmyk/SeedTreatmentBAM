"""Minimal static OOXML workbook reader used by the controlled XLSM QA/QC.

The reader deliberately does not use Excel, COM, LibreOffice, or a formula
engine.  It reads stored formulas and cached values from the OOXML package and
reconstructs shared-formula follower text by applying Excel's relative-copy
rules to the shared-formula master.
"""

from __future__ import annotations

import posixpath
import re
import zipfile
from dataclasses import dataclass
from pathlib import Path

from lxml import etree


NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS_PKG_REL = "http://schemas.openxmlformats.org/package/2006/relationships"
NS = {"m": NS_MAIN, "r": NS_REL, "pr": NS_PKG_REL}


def xml(zf: zipfile.ZipFile, name: str) -> etree._Element | None:
    try:
        return etree.fromstring(zf.read(name))
    except KeyError:
        return None


def normalize_target(base: str, target: str) -> str:
    if target.startswith("/"):
        return target.lstrip("/")
    return posixpath.normpath(posixpath.join(posixpath.dirname(base), target))


def relationships(zf: zipfile.ZipFile, rels_path: str, base_part: str) -> dict[str, dict[str, str]]:
    root = xml(zf, rels_path)
    if root is None:
        return {}
    result: dict[str, dict[str, str]] = {}
    for rel in root.findall(f"{{{NS_PKG_REL}}}Relationship"):
        target = rel.get("Target", "")
        mode = rel.get("TargetMode", "Internal")
        result[rel.get("Id", "")] = {
            "type": rel.get("Type", "").rsplit("/", 1)[-1],
            "target": target if mode == "External" else normalize_target(base_part, target),
            "target_mode": mode,
        }
    return result


def read_shared_strings(zf: zipfile.ZipFile) -> list[str]:
    root = xml(zf, "xl/sharedStrings.xml")
    if root is None:
        return []
    return ["".join(si.xpath(".//m:t/text()", namespaces=NS))
            for si in root.findall(f"{{{NS_MAIN}}}si")]


def column_number(letters: str) -> int:
    result = 0
    for char in letters.upper():
        result = result * 26 + ord(char) - 64
    return result


def column_letters(number: int) -> str:
    result = ""
    while number:
        number, remainder = divmod(number - 1, 26)
        result = chr(65 + remainder) + result
    return result


def split_ref(ref: str) -> tuple[int, int]:
    match = re.fullmatch(r"([A-Za-z]+)(\d+)", ref)
    if not match:
        raise ValueError(ref)
    return column_number(match.group(1)), int(match.group(2))


# Prefix is deliberately conservative: quoted worksheet names or a normal
# unquoted worksheet token.  The numeric row requirement prevents matching
# function names and most named ranges.
CELL_REF_RE = re.compile(
    r"(?P<prefix>(?:'(?:[^']|'')+'|[A-Za-z_][A-Za-z0-9_.]*)!)?"
    r"(?P<abscol>\$?)(?P<col>[A-Z]{1,3})(?P<absrow>\$?)(?P<row>[1-9][0-9]*)"
)


def translate_formula(formula: str, source_ref: str, target_ref: str) -> str:
    """Translate A1 references as Excel would when copying a formula."""
    source_col, source_row = split_ref(source_ref)
    target_col, target_row = split_ref(target_ref)
    delta_col, delta_row = target_col - source_col, target_row - source_row

    # Cell-like text inside Excel string literals is data, not a reference.
    pieces = re.split(r'("(?:[^"]|"")*")', formula)
    for index in range(0, len(pieces), 2):
        def replace(match: re.Match[str]) -> str:
            col = column_number(match.group("col"))
            row = int(match.group("row"))
            if not match.group("abscol"):
                col += delta_col
            if not match.group("absrow"):
                row += delta_row
            if col < 1 or row < 1:
                return "#REF!"
            return (
                (match.group("prefix") or "")
                + match.group("abscol") + column_letters(col)
                + match.group("absrow") + str(row)
            )
        pieces[index] = CELL_REF_RE.sub(replace, pieces[index])
    return "".join(pieces)


@dataclass(slots=True)
class Cell:
    worksheet: str
    ref: str
    value: str
    data_type: str
    formula: str = ""
    formula_type: str = ""
    shared_index: str = ""
    style_index: str = "0"
    formula_present: bool = False

    def number(self) -> float | None:
        try:
            return float(self.value)
        except (TypeError, ValueError):
            return None


class StaticWorkbook:
    """Read-only snapshot of workbook structure, formulas, and cached values."""

    def __init__(self, path: Path, selected_sheets: set[str] | None = None):
        self.path = path
        self.sheet_order: list[str] = []
        self.sheet_states: dict[str, str] = {}
        self.sheet_parts: dict[str, str] = {}
        self.cells: dict[str, dict[str, Cell]] = {}
        self.defined_names: dict[str, str] = {}
        self.calc_properties: dict[str, str] = {}
        self._read(selected_sheets)

    def _read(self, selected_sheets: set[str] | None) -> None:
        with zipfile.ZipFile(self.path) as zf:
            shared_strings = read_shared_strings(zf)
            workbook = xml(zf, "xl/workbook.xml")
            if workbook is None:
                raise ValueError("Missing xl/workbook.xml")
            rels = relationships(zf, "xl/_rels/workbook.xml.rels", "xl/workbook.xml")
            calc = workbook.find(f"{{{NS_MAIN}}}calcPr")
            if calc is not None:
                self.calc_properties = {key.rsplit("}", 1)[-1]: value
                                        for key, value in calc.attrib.items()}
            for node in workbook.xpath("./m:definedNames/m:definedName", namespaces=NS):
                if node.get("localSheetId") is None:
                    self.defined_names[node.get("name", "")] = node.text or ""
            for node in workbook.xpath("./m:sheets/m:sheet", namespaces=NS):
                name = node.get("name", "")
                self.sheet_order.append(name)
                self.sheet_states[name] = node.get("state", "visible")
                rid = node.get(f"{{{NS_REL}}}id", "")
                self.sheet_parts[name] = rels[rid]["target"]
                if selected_sheets is None or name in selected_sheets:
                    self.cells[name] = self._read_sheet(
                        zf, name, self.sheet_parts[name], shared_strings
                    )

    @staticmethod
    def _stored_value(cell: etree._Element, shared_strings: list[str]) -> str:
        kind = cell.get("t", "")
        value_node = cell.find(f"{{{NS_MAIN}}}v")
        raw = value_node.text if value_node is not None and value_node.text is not None else ""
        if kind == "s" and raw:
            try:
                return shared_strings[int(raw)]
            except (IndexError, ValueError):
                return raw
        if kind == "inlineStr":
            return "".join(cell.xpath(".//m:is//m:t/text()", namespaces=NS))
        if kind == "b":
            return "TRUE" if raw == "1" else "FALSE"
        return raw

    def _read_sheet(
        self, zf: zipfile.ZipFile, name: str, part: str, shared_strings: list[str]
    ) -> dict[str, Cell]:
        root = xml(zf, part)
        if root is None:
            return {}
        raw_cells = root.xpath("./m:sheetData/m:row/m:c", namespaces=NS)
        shared_masters: dict[str, tuple[str, str]] = {}
        for node in raw_cells:
            formula = node.find(f"{{{NS_MAIN}}}f")
            if formula is not None and formula.get("t") == "shared" and (formula.text or ""):
                shared_masters[formula.get("si", "")] = (node.get("r", ""), formula.text or "")

        result: dict[str, Cell] = {}
        for node in raw_cells:
            ref = node.get("r", "")
            formula_node = node.find(f"{{{NS_MAIN}}}f")
            formula_present = formula_node is not None
            formula_type = formula_node.get("t", "normal") if formula_present else ""
            shared_index = formula_node.get("si", "") if formula_present else ""
            formula = formula_node.text or "" if formula_present else ""
            if formula_present and formula_type == "shared" and not formula:
                master = shared_masters.get(shared_index)
                if master:
                    formula = translate_formula(master[1], master[0], ref)
            result[ref] = Cell(
                worksheet=name,
                ref=ref,
                value=self._stored_value(node, shared_strings),
                data_type=node.get("t", "n"),
                formula=formula,
                formula_type=formula_type,
                shared_index=shared_index,
                style_index=node.get("s", "0"),
                formula_present=formula_present,
            )
        return result

    def cell(self, sheet: str, ref: str) -> Cell | None:
        return self.cells.get(sheet, {}).get(ref.upper())

    def value(self, sheet: str, ref: str) -> str:
        cell = self.cell(sheet, ref)
        return cell.value if cell else ""

    def number(self, sheet: str, ref: str) -> float | None:
        cell = self.cell(sheet, ref)
        return cell.number() if cell else None

