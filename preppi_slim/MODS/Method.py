"""Common base class for PrePPI-SLiM per-protein methods."""
from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

from MODS.Genome import Genome


class Method:
    def __init__(self, **kwargs):
        self.step_parameters = dict(kwargs.pop("step_parameters", {}) or {})
        self.__dict__.update(self.step_parameters)
        self.__dict__.update(kwargs)
        self.name = self.pname()
        self.quiet = getattr(self, "quiet", "yes")
        self.init = getattr(self, "init", "yes")
        self.debug = getattr(self, "debug", "no")
        self.ginit()

    @classmethod
    def pname(cls):
        return cls.__name__

    def ginit(self):
        if not getattr(self, "gname", None) or not getattr(self, "gid", None):
            return
        self.genome = Genome(gname=self.gname)
        self.genome.mk_tgt_dir(self.gid)
        self.uniId = self.genome.seqUniId(self.gid)
        self.seq = self.genome.seq(self.gid)
        self.desc = self.genome.desc(self.gid)
        self.seqfn = self.genome.seqfn(self.gid)
        self.seqd = self.genome.seqd(self.gid)
        self.wrkdir = getattr(
            self, "wrkdir",
            str(Path(
                self.genome.home, "tmp", "pipeline_work", self.name, self.gid,
            )),
        )
        if self.init == "yes":
            Path(self.wrkdir).mkdir(mode=0o775, parents=True, exist_ok=True)
        self.gopher_groups = str(Path(self.seqd, "Orthology/gopher.ort"))
        self.motifs_elm = str(Path(self.seqd, "Motifs/slim_candidates.csv"))
        self.prds_elm = str(Path(self.seqd, "Motifs/prd_candidates.csv"))

    def execute(self, command, *, cwd=None, capture=False, env=None):
        if self.quiet != "yes" or self.debug == "yes":
            print("+", " ".join(map(str, command)), file=os.sys.stderr)
        return subprocess.run(
            [str(x) for x in command], cwd=cwd, env=env, check=True,
            text=True, capture_output=capture,
        )

    def run(self):
        return self.execute([self.cmd, *getattr(self, "pgmopts", [])], capture=True).stdout

    def count_jobs(self):
        if getattr(self, "sge_input", None) and Path(self.sge_input).is_file():
            with open(self.sge_input, encoding="utf-8") as handle:
                return sum(1 for _ in handle)
        return 1

    def count_tasks(self):
        return 1

    def complete(self, _step_args=None):
        outputs = getattr(self, "output", None)
        if outputs is None:
            return False
        if isinstance(outputs, (str, Path)):
            outputs = [outputs]
        return all(Path(x).exists() for x in outputs)

    def check(self, step_args=None):
        return self.complete(step_args)

    def prep(self):
        pass

    def process(self):
        Path(self.wrkdir, "process").touch()

    def clean_output(self):
        outputs = getattr(self, "output", [])
        if isinstance(outputs, (str, Path)):
            outputs = [outputs]
        for item in outputs:
            path = Path(item)
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink(missing_ok=True)
