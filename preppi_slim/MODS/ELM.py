"""Shared ELM/Pfam parsing and SLiM algorithms."""
from __future__ import annotations

import csv
import math
import re
from pathlib import Path

from MODS.Globals import ELM_CLASSES


def elm_definitions(path=ELM_CLASSES):
    definitions = {}
    with open(path, encoding="utf-8") as handle:
        for fields in csv.reader(handle, delimiter="\t"):
            if not fields or fields[0].startswith("#") or "Accession" in fields[0]:
                continue
            if len(fields) < 8:
                continue
            elm_class, pattern, domains = fields[1].strip('"'), fields[3].strip('"'), fields[7].strip('"')
            if domains == "NA" or "SMART:" in domains:
                continue
            definitions[elm_class] = {"regex": pattern, "domains": domains.split("|")}
    return definitions


def fasta_sequence(path):
    return "".join(
        line.strip() for line in Path(path).read_text().splitlines()
        if line and not line.startswith(">")
    )


def motif_matches(sequence, definitions):
    rows = []
    for elm_class in sorted(definitions):
        pattern = definitions[elm_class]["regex"].replace(r"\z", r"\Z")
        try:
            expression = re.compile(pattern)
        except re.error as error:
            raise ValueError(f"ELM regex for {elm_class} is not Python-compatible: {pattern}: {error}") from error
        anchored = bool(re.match(r"^\(*\^", pattern) or re.search(r"\$\)*$", pattern))
        if anchored:
            matches = expression.finditer(sequence)
        else:
            matches = (
                match for position in range(len(sequence))
                if (match := expression.match(sequence, position)) is not None
            )
        for match in matches:
            if match.end() == match.start():
                continue
            rows.append((elm_class, match.group(0), match.start() + 1, match.end()))
    return rows


def read_data_rows(path):
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#") or not line.strip():
                continue
            yield [part.strip() for part in (line.rstrip().split(",") if "," in line else line.split())]


def conservation_scores(path):
    rows = list(read_data_rows(path))
    if rows and rows[0][0].lower() == "residue_position":
        rows = rows[1:]
    return [float(row[2]) for row in rows if len(row) > 2]


def motif_is_conserved(scores, start, end, radius=30):
    for position in range(start, end + 1):
        left = max(1, position - radius)
        right = min(len(scores), position + radius)
        local = scores[left - 1:right]
        if not local or position > len(scores):
            return False
        if scores[position - 1] < sum(local) / len(local):
            return False
    return True


def information_content(aligned_sequences, query):
    positions = [index for index, residue in enumerate(query) if residue != "-"]
    base = -math.log2(0.05)
    values = []
    for column in positions:
        residues = [seq[column] for seq in aligned_sequences]
        gaps = residues.count("-")
        gap_fraction = gaps / len(residues)
        if gap_fraction >= 0.5:
            values.append(0.0)
            continue
        nongaps = [aa for aa in residues if aa != "-"]
        entropy = 0.0
        for aa in set(nongaps):
            fraction = nongaps.count(aa) / len(nongaps)
            entropy -= fraction * math.log2(fraction)
        values.append((1.0 - gap_fraction) * (base - entropy))
    return positions, values
