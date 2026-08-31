import os
import re
import shutil
from pathlib import Path

from MODS.Globals import BLASTCMD, GOPHER_BIN, GOPHER_DB
from MODS.Method import Method


class Gopher(Method):
    def ginit(self):
        super().ginit()
        self.qres = "mem=32G"
        if getattr(self, "seqd", None):
            self.output = [self.gopher_groups, str(Path(self.seqd, "Orthology/gopher.fas"))]

    def run(self):
        if len(self.gid) > 6:
            raise ValueError("Domains are not valid Gopher targets")
        lines = Path(self.seqfn).read_text().splitlines()
        header = lines[0] if lines else ""
        match = re.search(r"RepID=(.*)", header)
        representative = match.group(1).strip() if match else next(
            (item for item in re.split(r"[ |]", header) if "_" in item), None
        )
        if not representative:
            raise RuntimeError(f"No species identifier in FASTA header for {self.gid}")
        work = Path(self.wrkdir)
        (work / "input.fa").write_text(f">sp|{self.gid}|{representative}\n" + "\n".join(lines[1:]) + "\n")
        self.execute(
            ["/usr/bin/python3", GOPHER_BIN, "orthfas", "gopher=input.fa", f"orthdb={GOPHER_DB}", f"blastpath={BLASTCMD}"],
            cwd=work,
        )
        source = work / "ORTH" / f"{self.gid}.orth.fas"
        if not source.is_file():
            raise RuntimeError(f"Gopher did not create ortholog FASTA for {self.gid}")
        shutil.move(source, self.output[1])
        ids = work / "ORTH" / f"{self.gid}.orth.id"
        species = [m.group(1) for line in ids.read_text().splitlines() if (m := re.search(r"__(.*)", line))]
        Path(self.output[0]).write_text(
            f"# record_type=ortholog_species\n# genome={self.gname}\tprotein={self.gid}\n"
            "# method\tspecies_identifiers\n" + "gopher\t" + "|".join(species) + "|\n"
        )
        if self.debug != "yes":
            for directory in ("ORTH", "PARA", "BLAST"):
                shutil.rmtree(work / directory, ignore_errors=True)

    def count_jobs(self):
        return 0 if len(self.gid) > 6 else 1
