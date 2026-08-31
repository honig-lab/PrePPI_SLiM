import csv
from pathlib import Path

from MODS.ELM import information_content
from MODS.Globals import MUSCLE
from MODS.Method import Method


def read_fasta(path):
    records, name, seq = [], None, []
    for line in Path(path).read_text().splitlines():
        if line.startswith(">"):
            if name is not None:
                records.append((name, "".join(seq)))
            name, seq = line[1:].split()[0], []
        else:
            seq.append(line.strip())
    if name is not None:
        records.append((name, "".join(seq)))
    return records


class MuscleG(Method):
    def ginit(self):
        super().ginit()
        self.qres = "mem=12G,time=04:00:00"
        self.holds = "Gopher"
        if getattr(self, "seqd", None):
            self.input = str(Path(self.seqd, "Orthology/gopher.fas"))
            self.output = str(Path(self.seqd, "Aligns/residue_conservation.csv"))

    def run(self):
        alignment = Path(self.wrkdir, "gopher.muscle.fa")
        input_records = read_fasta(self.input)
        if not input_records:
            raise RuntimeError(f"Gopher FASTA is empty for {self.gid}")
        query_id = input_records[0][0]
        self.execute([MUSCLE, "-in", self.input, "-out", alignment, "-maxmb", "1000"])
        records = read_fasta(alignment)
        if not records:
            raise RuntimeError(f"MUSCLE created no alignment records for {self.gid}")
        query = next(
            (sequence for record_id, sequence in records if record_id == query_id),
            None,
        )
        if query is None:
            raise RuntimeError(
                f"MUSCLE alignment does not contain query {query_id}"
            )
        positions, scores = information_content([seq for _, seq in records], query)
        query_no_gap = query.replace("-", "")
        with open(self.output, "w", newline="", encoding="utf-8") as handle:
            handle.write("# record_type=per_residue_ortholog_conservation\n")
            handle.write(f"# genome={self.gname}\tprotein={self.gid}\n")
            writer = csv.writer(handle, lineterminator="\n")
            writer.writerow(("residue_position", "amino_acid", "information_content"))
            for index, score in enumerate(scores, 1):
                writer.writerow((index, query_no_gap[index - 1], score))
        alignment.unlink(missing_ok=True)
