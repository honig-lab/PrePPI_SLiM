from pathlib import Path
import os

from MODS.Globals import IFS_HOME, IUPRED as IUPRED_EXECUTABLE
from MODS.Method import Method


class IUPRED(Method):
    def ginit(self):
        super().ginit()
        if not getattr(self, "seqd", None):
            return
        self.output = str(Path(self.seqd, "disorder.fa"))

    def run(self):
        env = os.environ.copy()
        env.setdefault("IUPred_PATH", str(IFS_HOME / "shares/iupred"))
        result = self.execute(
            [IUPRED_EXECUTABLE, self.seqfn, "long"],
            capture=True,
            env=env,
        )
        symbols = []
        for line in result.stdout.splitlines():
            if line.startswith("#") or not line.strip():
                continue
            fields = line.split()
            if len(fields) >= 3:
                symbols.append("D" if float(fields[2]) > 0.5 else "-")
        if not symbols:
            raise RuntimeError(f"IUPred returned no residue scores for {self.gid}")
        Path(self.output).write_text(
            f">disorder genome={self.gname} protein={self.gid} encoding=D_if_IUPred_score_gt_0.5\n"
            + "".join(symbols) + "\n"
        )
        os.chmod(self.output, 0o664)
