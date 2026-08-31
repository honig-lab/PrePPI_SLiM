import csv
from pathlib import Path

from MODS.ELM import elm_definitions, fasta_sequence, motif_matches
from MODS.Method import Method


class FindMotifs_ELM(Method):
    def ginit(self):
        super().ginit()
        if getattr(self, "seqd", None):
            self.output = self.motifs_elm

    def run(self):
        rows = motif_matches(fasta_sequence(self.seqfn), elm_definitions())
        with open(self.output, "w", newline="", encoding="utf-8") as handle:
            handle.write("# record_type=ELM_SLIM_candidates\n")
            handle.write(f"# genome={self.gname}\tprotein={self.gid}\n")
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(("elm_class", "motif_sequence", "motif_start", "motif_end"))
            writer.writerows(rows)

    def count_jobs(self):
        return 0 if len(self.gid) > 6 else 1
