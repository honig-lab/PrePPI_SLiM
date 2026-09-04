"""Filesystem representation of one PrePPI-SLiM proteome."""
from __future__ import annotations

import csv
from contextlib import contextmanager
from functools import lru_cache
import os
import re
import tempfile
from pathlib import Path

from MODS.Globals import GENOME_DIRECTORY


SEQUENCE_COLUMNS = (
    "HFPD_ID", "UniProt_ID", "Description", "Sequence", "Length", "Source",
)


def _uniprot_id(description):
    """Extract the accession used previously in fasta/map_list."""
    for pattern in (
        r"(?:sp|tr)\|([^|\s]+)\|",
        r"UniRef100_([^\s|;]+)",
        r"HFPD_[^;]+;([A-Z0-9][A-Z0-9-]{5,14})(?:\s|$)",
        r"\|([A-Z0-9][A-Z0-9-]{5,14})\|",
        r"^([A-Z0-9][A-Z0-9-]{5,14})(?:\s|$)",
    ):
        match = re.search(pattern, description)
        if match:
            return match.group(1)
    return "NULL"


def _legacy_rows(home):
    """Expose an old fasta/id_list genome through the seqs.csv schema."""
    home = Path(home)
    id_list = home / "fasta/id_list"
    if not id_list.is_file():
        return []
    legacy_mapping = {}
    map_list = home / "fasta/map_list"
    if map_list.is_file():
        for line in map_list.read_text().splitlines():
            fields = line.split("\t")
            if len(fields) >= 2:
                legacy_mapping[fields[0].strip()] = fields[1].strip().lstrip(">")
    rows = []
    for target in (line.strip() for line in id_list.read_text().splitlines()):
        path = home / "fasta" / target
        if not target or not path.is_file():
            continue
        description = ""
        sequence = []
        with path.open(encoding="utf-8") as handle:
            for line in handle:
                if line.startswith(">"):
                    description = line[1:].strip()
                else:
                    sequence.append(line.strip())
        sequence_text = "".join(sequence)
        rows.append({
            "HFPD_ID": target,
            "UniProt_ID": legacy_mapping.get(target) or _uniprot_id(description),
            "Description": description,
            "Sequence": sequence_text,
            "Length": str(len(sequence_text)),
            "Source": "CDD" if "." in target else "Full-length",
        })
    return rows


@lru_cache(maxsize=32)
def sequence_rows(home):
    """Read the consolidated sequence table, falling back to a legacy genome."""
    home = Path(home)
    path = home / "seqs.csv"
    if not path.is_file():
        return _legacy_rows(home)
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        missing = set(SEQUENCE_COLUMNS) - set(reader.fieldnames or ())
        if missing:
            raise ValueError(f"{path} is missing columns: {sorted(missing)}")
        return [
            {column: (row.get(column) or "").strip() for column in SEQUENCE_COLUMNS}
            for row in reader
            if (row.get("HFPD_ID") or "").strip()
        ]


def target_ids(home):
    """Return target IDs from either seqs.csv or legacy id_list storage."""
    home = Path(home)
    sequence_table = home / "seqs.csv"
    if sequence_table.is_file():
        with sequence_table.open(newline="", encoding="utf-8-sig") as handle:
            targets = [
                (row.get("HFPD_ID") or "").strip()
                for row in csv.DictReader(handle)
            ]
    else:
        id_list = home / "fasta/id_list"
        targets = id_list.read_text().splitlines() if id_list.is_file() else []
    return [
        target for target in targets
        if target and (".g" not in target or os.environ.get("HFPD_WITHGAPS"))
    ]


@lru_cache(maxsize=256)
def sequence_record(home, target):
    """Read one protein without materializing every sequence in the genome."""
    home = Path(home)
    path = home / "seqs.csv"
    if path.is_file():
        with path.open("rb") as handle:
            header = handle.readline().decode("utf-8-sig")
            prefix = target.encode("utf-8") + b","
            for raw_line in handle:
                if not raw_line.startswith(prefix):
                    continue
                row = next(csv.DictReader([header, raw_line.decode("utf-8")]))
                return {
                    column: (row.get(column) or "").strip()
                    for column in SEQUENCE_COLUMNS
                }
        raise KeyError(target)

    legacy_path = home / "fasta" / target
    if not legacy_path.is_file():
        raise KeyError(target)
    description = ""
    sequence = []
    with legacy_path.open(encoding="utf-8") as handle:
        for line in handle:
            if line.startswith(">"):
                description = line[1:].strip()
            else:
                sequence.append(line.strip())
    uniprot_id = None
    map_list = home / "fasta/map_list"
    if map_list.is_file():
        with map_list.open(encoding="utf-8") as handle:
            for line in handle:
                fields = line.rstrip("\n").split("\t")
                if fields and fields[0].strip() == target and len(fields) >= 2:
                    uniprot_id = fields[1].strip().lstrip(">")
                    break
    sequence_text = "".join(sequence)
    return {
        "HFPD_ID": target,
        "UniProt_ID": uniprot_id or _uniprot_id(description),
        "Description": description,
        "Sequence": sequence_text,
        "Length": str(len(sequence_text)),
        "Source": "CDD" if "." in target else "Full-length",
    }


def uniprot_mapping(home):
    """Return HFPD-to-UniProt mappings from either genome representation."""
    home = Path(home)
    map_list = home / "fasta/map_list"
    if not (home / "seqs.csv").is_file() and map_list.is_file():
        mapping = {}
        for line in map_list.read_text().splitlines():
            fields = line.split("\t")
            if len(fields) >= 2:
                mapping[fields[0].strip()] = fields[1].strip().lstrip(">")
        return mapping
    return {
        row["HFPD_ID"]: row["UniProt_ID"].lstrip(">")
        for row in sequence_rows(home)
        if row["UniProt_ID"] and row["UniProt_ID"] != "NULL"
    }


class Genome:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)
        if not getattr(self, "gname", None):
            raise ValueError("Please specify a genome name")
        self.home = str(GENOME_DIRECTORY / self.gname)
        self.mk_tgt_dirs = getattr(self, "mk_tgt_dirs", "no")

    @property
    def sequence_table(self):
        return Path(self.home, "seqs.csv")

    def init(self, fasta_file, **kwargs):
        self.mk_tgt_dirs = kwargs.get("mk_tgt_dirs", self.mk_tgt_dirs)
        for name in ("", "Seqs", "tmp", "Pipeline", "Interactions"):
            Path(self.home, name).mkdir(mode=0o775, parents=True, exist_ok=True)
        targets = self.create_sequence_table(fasta_file)
        if self.mk_tgt_dirs == "yes":
            for target in targets:
                self.mk_tgt_dir(target)
        return True

    @staticmethod
    def _input_records(fasta_file):
        records = []
        header = None
        sequence = []
        with open(fasta_file, encoding="utf-8") as handle:
            for line in handle:
                if line.startswith(">"):
                    if header is not None:
                        records.append((header, "".join(sequence)))
                    header, sequence = line[1:].strip(), []
                elif header is not None:
                    sequence.append("".join(line.split()))
            if header is not None:
                records.append((header, "".join(sequence)))
        if not records:
            raise ValueError(f"No FASTA records found in {fasta_file}")
        return records

    def create_sequence_table(self, fasta_file):
        """Add FASTA records to seqs.csv without creating per-target FASTAs."""
        existing_rows = sequence_rows(self.home)
        existing_ids = {row["HFPD_ID"] for row in existing_rows}
        next_id = max(
            [int(target) for target in existing_ids if re.fullmatch(r"\d{6}", target)]
            or [0]
        ) + 1
        targets = []
        for original_description, sequence in self._input_records(fasta_file):
            match = re.search(r"HFPD_(\d{6}[.A-Za-z0-9_-]*)", original_description)
            target = match.group(1) if match else f"{next_id:06d}"
            if not match:
                next_id += 1
            targets.append(target)
            if target in existing_ids:
                continue
            description = re.sub(
                rf"^HFPD_{re.escape(target)};?", "", original_description,
            ).strip()
            existing_rows.append({
                "HFPD_ID": target,
                "UniProt_ID": _uniprot_id(description),
                "Description": description,
                "Sequence": sequence,
                "Length": str(len(sequence)),
                "Source": "CDD" if "." in target else "Full-length",
            })
            existing_ids.add(target)

        temporary = self.sequence_table.with_suffix(".csv.new")
        with temporary.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(
                handle, fieldnames=SEQUENCE_COLUMNS, lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(existing_rows)
        temporary.replace(self.sequence_table)
        sequence_rows.cache_clear()
        sequence_record.cache_clear()
        return targets

    def mk_fasta_dir(self, fasta_file):
        """Backward-compatible alias for the former setup method."""
        return self.create_sequence_table(fasta_file)

    def mk_tgt_dir(self, target):
        seq_dir = Path(self.home, "Seqs", target)
        for directory in (
            seq_dir, seq_dir / "Aligns", seq_dir / "Motifs",
            seq_dir / "Orthology",
        ):
            directory.mkdir(mode=0o775, parents=True, exist_ok=True)

    def get_target_list(self):
        targets = target_ids(self.home)
        if not targets:
            raise FileNotFoundError(
                f"No targets found in {self.sequence_table} or "
                f"{Path(self.home, 'fasta/id_list')}"
            )
        return targets

    def tgt_list_fn(self):
        legacy = Path(self.home, "fasta/id_list")
        return str(legacy if legacy.is_file() else self.sequence_table)

    def get_tgt_id(self, index):
        return self.get_target_list()[index - 1]

    def seqfn(self, target):
        """Return a legacy persistent FASTA path, which may not exist."""
        return str(Path(self.home, "fasta", target))

    def seqd(self, target):
        return str(Path(self.home, "Seqs", target))

    def _row(self, target):
        try:
            return sequence_record(self.home, target)
        except KeyError as error:
            raise KeyError(
                f"Unknown HFPD ID {target} in genome {self.gname}"
            ) from error

    def seq_data(self, target):
        row = self._row(target)
        return row["Sequence"], row["Description"]

    def seq(self, target):
        return self.seq_data(target)[0]

    def desc(self, target):
        return self.seq_data(target)[1]

    def fasta_text(self, target):
        sequence, description = self.seq_data(target)
        return f">HFPD_{target};{description}\n{sequence}\n"

    @contextmanager
    def temporary_fasta(self, target, directory=None):
        """Yield legacy FASTA directly or a short-lived FASTA for new genomes."""
        legacy = Path(self.seqfn(target))
        if legacy.is_file():
            yield legacy
            return
        root = Path(directory or Path(self.home, "tmp"))
        root.mkdir(mode=0o775, parents=True, exist_ok=True)
        descriptor, filename = tempfile.mkstemp(
            prefix=f"{target}.", suffix=".fasta", dir=root,
        )
        path = Path(filename)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(self.fasta_text(target))
            yield path
        finally:
            path.unlink(missing_ok=True)

    def seqUniId(self, target):
        row = self._row(target)
        if row["UniProt_ID"] and row["UniProt_ID"] != "NULL":
            return row["UniProt_ID"]
        path = Path(self.seqd(target), "Aligns/Uniprot_info.txt")
        if not path.exists():
            return "NULL"
        return (path.read_text().splitlines() or ["NULL"])[0].split("\t")[0] or "NULL"

    def seqUniId_original(self, target):
        row = self._row(target)
        return row["UniProt_ID"] or "NULL"
