import csv
import os
from pathlib import Path

from MODS.ELM import elm_definitions
from MODS.Globals import HMMS, JACKHAMMER_DIR, MAIN_DIRECTORY, PFAM_PERL
from MODS.Method import Method


class FindPRDs_ELM(Method):
    def ginit(self):
        super().ginit()
        self.qres = "mem=10G"
        if getattr(self, "seqd", None):
            self.output = [self.prds_elm, str(Path(self.seqd, "Motifs", f"{self.gid}.pfam"))]

    def run(self):
        prd_file, pfam_file = self.output
        env = os.environ.copy()
        env["PATH"] = env.get("PATH", "") + os.pathsep + str(JACKHAMMER_DIR)
        vendor = MAIN_DIRECTORY / "SCR/PfamScan/pfam_scan.pl"
        Path(pfam_file).unlink(missing_ok=True)
        with self.genome.temporary_fasta(self.gid, self.wrkdir) as fasta_file:
            self.execute(
                [PFAM_PERL, "-w", vendor, "-fasta", fasta_file,
                 "-dir", HMMS, "-outfile", pfam_file],
                env=env,
            )
        if not Path(pfam_file).exists():
            raise RuntimeError(f"PfamScan did not create {pfam_file}")
        original = Path(pfam_file).read_text()
        Path(pfam_file).write_text(
            f"# record_type=PfamScan_domains\n# genome={self.gname}\tprotein={self.gid}\n" + original
        )
        domains = {}
        for elm_class, record in elm_definitions().items():
            for domain in record["domains"]:
                domains.setdefault(domain, []).append(elm_class)
        hits = []
        for line in original.splitlines():
            if not line.startswith("HFPD_"):
                continue
            fields = line.split()
            if len(fields) >= 7 and fields[6] in domains:
                for elm_class in sorted(domains[fields[6]]):
                    hits.append((elm_class, fields[6], fields[1], fields[2]))
        with open(prd_file, "w", newline="", encoding="utf-8") as handle:
            handle.write("# record_type=ELM_peptide_recognition_domains\n")
            handle.write(f"# genome={self.gname}\tprotein={self.gid}\n")
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(("elm_class", "pfam_domain", "prd_start", "prd_end"))
            writer.writerows(sorted(hits))
