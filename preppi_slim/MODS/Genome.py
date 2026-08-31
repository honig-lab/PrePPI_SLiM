"""Filesystem representation of one PrePPI-SLiM proteome."""
from __future__ import annotations

import os
import re
from pathlib import Path

from MODS.Globals import GENOME_DIRECTORY


class Genome:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)
        if not getattr(self, "gname", None):
            raise ValueError("Please specify a genome name")
        self.home = str(GENOME_DIRECTORY / self.gname)
        self.mk_tgt_dirs = getattr(self, "mk_tgt_dirs", "no")

    def init(self, fasta_file, **kwargs):
        self.mk_tgt_dirs = kwargs.get("mk_tgt_dirs", self.mk_tgt_dirs)
        for name in ("", "Seqs", "tmp", "Pipeline", "Interactions"):
            Path(self.home, name).mkdir(mode=0o775, parents=True, exist_ok=True)
        targets = self.mk_fasta_dir(fasta_file)
        if self.mk_tgt_dirs == "yes":
            for target in targets:
                self.mk_tgt_dir(target)
        return True

    def mk_fasta_dir(self, fasta_file):
        fasta_dir = Path(self.home, "fasta")
        fasta_dir.mkdir(mode=0o775, exist_ok=True)
        id_list = fasta_dir / "id_list"
        existing = id_list.read_text().splitlines() if id_list.exists() else []
        next_id = max([int(x) for x in existing if re.fullmatch(r"\d{6}", x)] or [0]) + 1
        records = []
        header = None
        sequence = []
        with open(fasta_file, encoding="utf-8") as handle:
            for line in handle:
                if line.startswith(">"):
                    if header is not None:
                        records.append((header, "".join(sequence)))
                    header, sequence = line.rstrip("\n"), []
                elif header is not None:
                    sequence.append(line)
            if header is not None:
                records.append((header, "".join(sequence)))
        if not records:
            raise ValueError(f"No FASTA records found in {fasta_file}")
        targets, new_targets = [], []
        with id_list.open("a", encoding="utf-8") as ids:
            for original_header, sequence_text in records:
                match = re.search(r"HFPD_(\d{6}[.a-z0-9_-]*)", original_header)
                target = match.group(1) if match else f"{next_id:06d}"
                if not match:
                    next_id += 1
                header_text = original_header if match else f">HFPD_{target};{original_header[1:]}"
                targets.append(target)
                target_file = fasta_dir / target
                if target_file.exists():
                    continue
                target_file.write_text(header_text + "\n" + sequence_text, encoding="utf-8")
                ids.write(target + "\n")
                new_targets.append(target)
        self.create_mapping(new_targets)
        return targets

    def mk_tgt_dir(self, target):
        seq_dir = Path(self.home, "Seqs", target)
        work_dir = Path(self.home, "Pipeline", f"Pipeline_{target}")
        for directory in (seq_dir, seq_dir / "Aligns", seq_dir / "Motifs", seq_dir / "Orthology", work_dir):
            directory.mkdir(mode=0o775, parents=True, exist_ok=True)
        link = seq_dir / "Pipeline"
        if not link.exists() and not link.is_symlink():
            link.symlink_to(work_dir)

    def get_target_list(self):
        path = Path(self.home, "fasta/id_list")
        if not path.is_file():
            raise FileNotFoundError(f"Cannot open {path}")
        return [x.strip() for x in path.read_text().splitlines() if x.strip() and (".g" not in x or os.environ.get("HFPD_WITHGAPS"))]

    def tgt_list_fn(self): return str(Path(self.home, "fasta/id_list"))
    def get_tgt_id(self, index): return self.get_target_list()[index - 1]
    def seqfn(self, target): return str(Path(self.home, "fasta", target))
    def seqd(self, target): return str(Path(self.home, "Seqs", target))

    def seq_data(self, target):
        description, sequence = "", []
        with open(self.seqfn(target), encoding="utf-8") as handle:
            for line in handle:
                if line.startswith(">"):
                    description = line[1:].strip()
                else:
                    sequence.append(line.strip())
        return "".join(sequence), description

    def seq(self, target): return self.seq_data(target)[0]
    def desc(self, target): return self.seq_data(target)[1]

    def seqUniId(self, target):
        path = Path(self.seqd(target), "Aligns/Uniprot_info.txt")
        if not path.exists(): return "NULL"
        return (path.read_text().splitlines() or ["NULL"])[0].split("\t")[0] or "NULL"

    def seqUniId_original(self, target):
        description = self.desc(target)
        for pattern in (r"HFPD_[^;]+;([A-Z0-9]{6,10})", r"UniRef100_([A-Z0-9]{6,10})", r"\|([A-Z0-9]{6,10})\|"):
            match = re.search(pattern, description)
            if match: return match.group(1)
        return self.seqUniId(target)

    def create_mapping(self, targets):
        path = Path(self.home, "fasta/map_list")
        with path.open("a", encoding="utf-8") as output:
            for target in targets:
                if len(target) != 6: continue
                external = self.seqUniId_original(target)
                output.write(f"{target}\t>{target if external == 'NULL' else external}\n")
