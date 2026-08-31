import csv
from pathlib import Path

from MODS.ELM import conservation_scores, motif_is_conserved, read_data_rows
from MODS.Method import Method


class MotifConsv(Method):
    def ginit(self):
        super().ginit()
        self.holds = "MuscleG,FindMotifs_ELM"
        if getattr(self, "seqd", None):
            self.input = str(Path(self.seqd, "Aligns/residue_conservation.csv"))
            self.input2 = str(Path(self.seqd, "Motifs/slim_candidates.csv"))
            self.output = str(Path(self.seqd, "Motifs/conserved_slims.csv"))

    def run(self):
        if any(suffix in self.gid for suffix in (".e", ".d", ".g")):
            return
        scores = conservation_scores(self.input)
        rows = list(read_data_rows(self.input2))
        if rows and rows[0][0].lower() == "elm_class":
            rows = rows[1:]
        conserved = []
        for row in rows:
            if len(row) >= 4 and motif_is_conserved(scores, int(row[2]), int(row[3])):
                conserved.append((row[0], row[1], row[2]))
        with open(self.output, "w", newline="", encoding="utf-8") as handle:
            handle.write("# record_type=conserved_ELM_SLIM_candidates\n")
            handle.write(f"# genome={self.gname}\tprotein={self.gid}\n")
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(("elm_class", "motif_sequence", "motif_start"))
            writer.writerows(conserved)
