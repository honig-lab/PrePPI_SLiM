"""Enumerate ELM SLiM/PRD-compatible pairs in one or both directions."""
from __future__ import annotations

import csv
import gzip
import re
from pathlib import Path

from MODS.Genome import Genome
from MODS.Method import Method


def first_existing(*paths):
    return next((Path(path) for path in paths if Path(path).exists()), None)


def data_dict_rows(path, legacy_fields):
    """Read a headered CSV/TSV or a legacy headerless whitespace table."""
    if path is None:
        return []
    with open(path, encoding="utf-8") as handle:
        lines = [line for line in handle if line.strip() and not line.startswith("#")]
    if not lines:
        return []

    def fields(line):
        if "," in line:
            return next(csv.reader([line]))
        return line.split()

    first = [value.strip() for value in fields(lines[0])]
    if "elm_class" in first:
        header = first
        data_lines = lines[1:]
    else:
        header = list(legacy_fields)
        data_lines = lines

    rows = []
    for line_number, line in enumerate(data_lines, 2 if data_lines is not lines else 1):
        values = [value.strip() for value in fields(line)]
        if len(values) != len(header):
            raise ValueError(
                f"Malformed annotation row in {path} at data line {line_number}: "
                f"expected {len(header)} columns, found {len(values)}"
            )
        rows.append(dict(zip(header, values)))
    return rows


class ProtPeptide_ELM(Method):
    @classmethod
    def pname(cls):
        return "ProtPeptide_ELM"

    def ginit(self):
        super().ginit()
        self.orientation = getattr(self, "orientation", "motif")
        self.qres = "time=24:00:00" if self.orientation == "both" else "time=12:00:00"
        if not getattr(self, "seqd", None):
            return
        self.partner_gname = getattr(self, "external", self.gname)
        self.genome2 = Genome(gname=self.partner_gname)
        if not Path(self.genome2.home).is_dir():
            raise FileNotFoundError(f"Partner genome does not exist: {self.genome2.home}")
        self.run_tag = re.sub(r"[^A-Za-z0-9_.-]+", "_", getattr(self, "run_tag", f"{self.orientation}_{self.partner_gname}"))
        self.wrkdir = str(Path(
            self.genome.home, "tmp", "pipeline_work", "ProtPeptide_ELM",
            self.run_tag, self.gid,
        ))
        if self.init == "yes":
            Path(self.wrkdir).mkdir(mode=0o775, parents=True, exist_ok=True)
        if self.orientation == "both" and self.gname != self.partner_gname:
            name = f"{self.gname}_vs_{self.partner_gname}_prd_slim_candidates.csv.gz"
        else:
            motif_genome, prd_genome = (
                (self.partner_gname, self.gname)
                if self.orientation == "prd"
                else (self.gname, self.partner_gname)
            )
            name = f"{motif_genome}_slim_{prd_genome}_prd_candidates.csv.gz"
        self.output = str(Path(self.seqd, "Motifs", re.sub(r"[^A-Za-z0-9_.-]+", "_", name)))

    @staticmethod
    def _disorder(path):
        if not path.exists():
            return {}
        symbols = "".join(
            line.strip() for line in path.read_text().splitlines()
            if line and not line.startswith(("#", ">"))
        )
        return {index: symbol == "D" for index, symbol in enumerate(symbols, 1)}

    def _motifs(self, genome, protein):
        base = Path(genome.home, "Seqs", protein)
        motif_file = first_existing(base / "Motifs/slim_candidates.csv", base / "Motifs/motif_elm.txt")
        conservation_file = first_existing(base / "Motifs/conserved_slims.csv", base / "Motifs/motif_elm.csv")
        conserved = {
            (row.get("elm_class"), row.get("motif_sequence"), row.get("motif_start"))
            for row in data_dict_rows(
                conservation_file,
                ("elm_class", "motif_sequence", "motif_start"),
            )
        }
        disorder = self._disorder(base / "disorder.fa")
        records = []
        for row in data_dict_rows(
            motif_file,
            ("elm_class", "motif_sequence", "motif_start", "motif_end"),
        ):
            start = int(row["motif_start"])
            end = int(row.get("motif_end") or start + len(row["motif_sequence"]) - 1)
            fraction = sum(disorder.get(position, False) for position in range(start, end + 1)) / (end - start + 1)
            records.append({
                "elm_class": row["elm_class"], "motif_sequence": row["motif_sequence"],
                "motif_start": start, "motif_end": end,
                "conserved": int((row["elm_class"], row["motif_sequence"], str(start)) in conserved),
                "disordered_fraction": fraction,
            })
        return records

    def _prds(self, genome, protein):
        base = Path(genome.home, "Seqs", protein, "Motifs")
        path = first_existing(base / "prd_candidates.csv", base / "prd_elm.txt")
        records = []
        for row in data_dict_rows(
            path,
            ("elm_class", "pfam_domain", "prd_start", "prd_end"),
        ):
            records.append({
                "elm_class": row["elm_class"],
                "prd_name": row.get("pfam_domain") or row.get("prd_name") or "NA",
                "prd_start": int(row["prd_start"]), "prd_end": int(row["prd_end"]),
            })
        return records

    def _matching(self, motif_genome, motif_protein, motifs, prd_genome, prd_protein, prds, anchor_role):
        for motif in motifs:
            for prd in prds:
                if motif["elm_class"] != prd["elm_class"]:
                    continue
                yield {
                    "motif_genome": motif_genome, "prd_genome": prd_genome,
                    "anchor_genome": self.gname, "anchor_protein": self.gid,
                    "anchor_role": anchor_role, "motif_protein": motif_protein,
                    "prd_protein": prd_protein, "prd_name": prd["prd_name"],
                    "elm_class": motif["elm_class"], "prd_start": prd["prd_start"],
                    "prd_end": prd["prd_end"], "motif_sequence": motif["motif_sequence"],
                    "motif_start": motif["motif_start"], "motif_end": motif["motif_end"],
                    "conserved": motif["conserved"],
                    "disordered_fraction": motif["disordered_fraction"],
                }

    def run(self):
        if self.orientation not in {"motif", "prd", "both"}:
            raise ValueError(f"Unknown orientation: {self.orientation}")
        rows = []
        if self.orientation in {"motif", "both"}:
            motifs = self._motifs(self.genome, self.gid)
            for partner in self.genome2.get_target_list():
                rows.extend(self._matching(
                    self.gname, self.gid, motifs, self.partner_gname, partner,
                    self._prds(self.genome2, partner), "motif",
                ))
        if self.orientation == "prd" or (self.orientation == "both" and self.gname != self.partner_gname):
            prds = self._prds(self.genome, self.gid)
            for partner in self.genome2.get_target_list():
                rows.extend(self._matching(
                    self.partner_gname, partner, self._motifs(self.genome2, partner),
                    self.gname, self.gid, prds, "prd",
                ))
        fields = (
            "motif_genome", "prd_genome", "anchor_genome", "anchor_protein",
            "anchor_role", "motif_protein", "prd_protein", "prd_name",
            "elm_class", "prd_start", "prd_end", "motif_sequence",
            "motif_start", "motif_end", "conserved", "disordered_fraction",
        )
        with gzip.open(self.output, "wt", newline="", encoding="utf-8") as handle:
            handle.write("# record_type=PrePPI-SLiM_PRD-SLiM_candidates\n")
            handle.write(
                f"# anchor_genome={self.gname}\tpartner_genome={self.partner_gname}"
                f"\torientation={self.orientation}\n"
            )
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(sorted(rows, key=lambda row: tuple(str(row[x]) for x in fields)))

    def count_jobs(self):
        return 0 if len(self.gid) > 6 else 1
