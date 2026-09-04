"""Shared SLURM pipeline controller for PrePPI-SLiM."""
from __future__ import annotations

import importlib
import json
import os
import random
import re
import shutil
import string
import subprocess
import sys
import time as time_module
from datetime import datetime
from pathlib import Path

from MODS.Genome import Genome
from MODS.Globals import CONDA_ENV, HFPD_SCR, MAIN_DIRECTORY, MAX_ARRAY_VAL, PYTHON
from MODS.PipelineState import StatusTable, output_health

STEP_MODULES = {
    "IUPRED": "IUPRED", "FindMotifs_ELM": "FindMotifs",
    "FindPRDs_ELM": "FindPRDs", "Gopher": "Orthologs",
    "MuscleG": "MultiAlign", "MotifConsv": "MotifConsv",
    "ProtPeptide_ELM": "ProtPeptide_ELM",
}


class Pipeline:
    """SM-compatible controller preserving the existing SLiM state files."""

    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)
        if not getattr(self, "name", None) or not getattr(self, "gname", None):
            raise ValueError("Pipeline name and genome name are required")
        self.genome = Genome(gname=self.gname)
        if not Path(self.genome.home).is_dir():
            raise FileNotFoundError(f"Genome {self.gname} does not exist")
        self.pipedir = str(Path(self.genome.home, "Pipeline", f"{self.name}.pip"))
        for directory in ("", "timings", "completed", "incomplete"):
            Path(self.pipedir, directory).mkdir(mode=0o775, parents=True, exist_ok=True)
        for suffix in ("stage", "steps", "jstat"):
            Path(self.pipedir, f"{self.name}.{suffix}").touch()
        Path(self.pipedir, "running").touch()
        self.stepsfn = str(Path(self.pipedir, f"{self.name}.steps"))
        self.debug = getattr(self, "debug", "no")
        self.qflag = "yes"
        self.status_table = StatusTable(Path(self.pipedir, "status.csv"))

    @staticmethod
    def method_outputs(method):
        output = getattr(method, "output", None)
        if output is None:
            return []
        if isinstance(output, (str, Path)):
            return [str(output)]
        return [str(path) for path in output if path]

    def initialize_status(self, targets=None):
        """Create one durable row per target and configured subtask."""
        rows = []
        targets = targets or self.genome.get_target_list()
        for gid in targets:
            for sname in self.steps():
                method = self.get_step_class(sname)(
                    gname=self.gname,
                    gid=gid,
                    init="no",
                    step_parameters=self.step_arg(sname),
                )
                outputs = self.method_outputs(method)
                inspection = output_health(outputs)
                completed = method.complete()
                rows.append({
                    "hfpd_id": gid,
                    "subtask_id": sname,
                    "work_directory": method.wrkdir,
                    "status": "completed" if completed else "pending",
                    **inspection,
                    "health": "healthy" if completed else "pending",
                })
        self.status_table.initialize(rows)

    @staticmethod
    def controller_state(info):
        if "complete 0 jobs" in info:
            return "skipped", "not_applicable"
        if "fail" in info or "predecessor" in info:
            return "failed", "failed"
        if "complete" in info:
            return "completed", "healthy"
        if "submit" in info:
            return "submitted", "active"
        if "queued" in info:
            return "queued", "active"
        if "ready" in info:
            return "ready", "ready"
        if "holding" in info:
            return "blocked", "waiting"
        return "pending", "pending"

    def record_status(self, gid, sname, info):
        """Mirror legacy controller history into status.csv."""
        method = self.get_step_class(sname)(
            gname=self.gname,
            gid=gid,
            init="no",
            step_parameters=self.step_arg(sname),
        )
        outputs = self.method_outputs(method)
        state, health = self.controller_state(info)
        current = self.status_table.get(gid, sname)
        rank = {
            "pending": 0,
            "blocked": 1,
            "ready": 2,
            "queued": 3,
            "submitted": 4,
            "running": 5,
            "awaiting_postprocess": 6,
            "completed": 7,
            "skipped": 7,
            "failed": 7,
        }
        if rank.get(current.get("status"), -1) > rank.get(state, -1):
            return
        values = {
            "status": state,
            "health": health,
            "message": info,
            "expected_outputs": json.dumps(outputs, separators=(",", ":")),
        }
        if state == "queued":
            values["queued_at"] = datetime.now().isoformat(timespec="seconds")
        if state in {"completed", "failed"}:
            values["finished_at"] = datetime.now().isoformat(timespec="seconds")
            inspection = output_health(outputs)
            values.update({
                key: value for key, value in inspection.items()
                if key != "health"
            })
            if state == "completed" and inspection["health"] != "healthy":
                values["status"] = "failed"
                values["health"] = inspection["health"]
                values["message"] = (
                    f"{info}; controller reported completion but expected "
                    "output is missing"
                )
            else:
                values["health"] = (
                    inspection["health"] if state == "completed" else "failed"
                )
        elif state == "skipped":
            values.update({
                "finished_at": datetime.now().isoformat(timespec="seconds"),
                "expected_outputs": "[]",
                "outputs_complete": "not_applicable",
                "outputs_present": "[]",
                "missing_outputs": "[]",
                "output_count": 0,
            })
        self.status_table.update(gid, sname, **values)

    def cleanup_transient_state(self):
        """Retain only status.csv after a healthy non-debug controller run."""
        if self.debug == "yes":
            return False
        if not self.status_table.all_terminal_and_healthy():
            print(
                f"Retaining {self.pipedir} scheduler artifacts because "
                "status.csv contains incomplete or failed rows.",
                file=sys.stderr,
            )
            return False
        rows = self.status_table.rows()
        method_classes = {
            sname: self.step_arg(sname).get("class", sname)
            for sname in self.steps()
        }
        for child in list(Path(self.pipedir).iterdir()):
            if child.name == "status.csv":
                continue
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink(missing_ok=True)
        self.status_table.remove_lock()

        for row in rows:
            gid = row.get("hfpd_id", "")
            sname = row.get("subtask_id", "")
            if not gid or not sname:
                continue
            legacy_parent = Path(
                self.genome.home, "Pipeline", f"Pipeline_{gid}",
            )
            for method_name in {sname, method_classes.get(sname, sname)}:
                legacy_method = legacy_parent / method_name
                if legacy_method.is_dir():
                    shutil.rmtree(legacy_method)
            try:
                legacy_parent.rmdir()
            except OSError:
                pass
            old_link = Path(self.genome.home, "Seqs", gid, "Pipeline")
            if old_link.is_symlink():
                old_link.unlink()
        return True

    def add_step(self, sname, argstr=None, class_=None, **parameters):
        args = {}
        if argstr:
            parts = argstr.split(",")
            if len(parts) % 2:
                raise ValueError(f"Malformed step parameter string: {argstr}")
            args.update(dict(zip(parts[::2], parts[1::2])))
        args.update({key: str(value) for key, value in parameters.items()})
        if class_:
            args["class"] = class_
        Path(self.pipedir, f"{sname}.tgt").touch()
        encoded = "".join(f"<{key}>{value}</{key}>" for key, value in args.items())
        with open(self.stepsfn, "a", encoding="utf-8") as handle:
            handle.write(f"{sname}\t{encoded}\n")
        if "external" in args:
            Path(self.pipedir, f"{sname}.g2").write_text(args["external"])

    def steps(self):
        path = Path(self.stepsfn + ".focus") if Path(self.stepsfn + ".focus").exists() else Path(self.stepsfn)
        values = [line.split("\t", 1)[0].strip() for line in path.read_text().splitlines() if line.strip()]
        if not values:
            raise RuntimeError(f"No pipeline steps found in {path}")
        return values

    def step_arg(self, name):
        output = {}
        for line in Path(self.stepsfn).read_text().splitlines():
            if line.split("\t", 1)[0] == name:
                output.update(re.findall(r"<(\w+)>([^<>]*)</\w+>", line.split("\t", 1)[1] if "\t" in line else ""))
        return output

    def get_step_class(self, name):
        args = self.step_arg(name)
        class_name = args.get("class", name)
        module = importlib.import_module(f"MODS.{args.get('module', STEP_MODULES.get(name, name))}")
        return getattr(module, class_name)

    def qsub(self, execute="yes"):
        script = Path(self.pipedir, f"{self.name}.sh")
        debug = " --debug" if self.debug == "yes" else ""
        stdout = f"{self.name}.{self.gname}.o%j" if self.debug == "yes" else "/dev/null"
        stderr = f"{self.name}.{self.gname}.e%j" if self.debug == "yes" else "/dev/null"
        script.write_text(
            "#!/bin/bash\n"
            f"#SBATCH --chdir={self.pipedir}\n#SBATCH --job-name={self.name}.{self.gname}\n"
            f"#SBATCH --time=24:00:00\n#SBATCH --output={stdout}\n"
            f"#SBATCH --error={stderr}\nset -euo pipefail\n"
            f"export HFPD_DIR={MAIN_DIRECTORY}\n"
            f"export HFPD_DATA_DIR={os.environ.get('HFPD_DATA_DIR', Path(self.genome.home).parent)}\n"
            f"export PYTHONPATH={MAIN_DIRECTORY}:${{PYTHONPATH:-}}\n"
            f"export PATH={CONDA_ENV / 'bin'}:$PATH\nexport CONDA_PREFIX={CONDA_ENV}\n"
            f"if ! {PYTHON} {HFPD_SCR / 'run_pipeline.py'} {self.name} {self.gname}{debug}; then\n"
            f"  grep -q '^Pipeline failed:' {self.pipedir}/{self.name}.stage 2>/dev/null || "
            f"echo 'Pipeline controller failed. Inspect the SLURM error log.' > {self.pipedir}/{self.name}.stage\n"
            "  exit 1\nfi\n"
        )
        script.chmod(0o775)
        if execute == "yes":
            result = subprocess.run(["sbatch", str(script)], text=True, capture_output=True, check=True)
            print(result.stdout, end="", file=sys.stderr)

    @staticmethod
    def write_resource_string(qres):
        lines = []
        for element in re.split(r"[,;]", qres):
            key, value = element.split("=", 1)
            if key == "mem":
                lines.append(f"#SBATCH --mem={value}")
            elif key == "time":
                hours, minutes, seconds = map(int, value.split(":"))
                lines.append(f"#SBATCH --time={hours // 24}-{hours % 24:02d}:{minutes:02d}:{seconds:02d}")
            elif key == "cpus":
                lines.append(f"#SBATCH --cpus-per-task={int(value)}")
            else:
                raise ValueError(f"Unknown resource type: {key}")
        return "\n".join(lines) + ("\n" if lines else "")

    def submit_block(self, sname, jobstat):
        target_path = Path(self.pipedir, f"{sname}.tgt")
        jobs = [line for line in target_path.read_text().splitlines() if line.strip()]
        if not jobs:
            return None
        first_gid = jobs[0].split()[0]
        method = self.get_step_class(sname)(gname=self.gname, gid=first_gid, step_parameters=self.step_arg(sname))
        cap = min(getattr(method, "jcap", MAX_ARRAY_VAL), MAX_ARRAY_VAL)
        selected, total = [], 0
        for line in jobs:
            gid, count_text = line.split()
            count = int(count_text)
            if total + count > cap:
                break
            selected.append((gid, count))
            total += count
        if not selected:
            return None
        token = "".join(random.choices(string.ascii_letters + string.digits, k=5))
        block_name = f"{sname}_{token}.tgt"
        block = Path(self.pipedir, block_name)
        block.write_text("".join(f"{gid}\t{count}\n" for gid, count in selected))
        block.chmod(0o664)
        now = self.time()
        for gid, _ in selected:
            key = f"{gid}:{sname}"
            jobstat[key] = jobstat.get(key, "") + f"({now} submit {block_name})"
        remainder = jobs[len(selected):]
        target_path.write_text("\n".join(remainder) + ("\n" if remainder else ""))
        return self.qsub_block(block_name, sname, total, getattr(method, "qres", None))

    def qsub_block(self, block_name, sname, total, qres=None):
        active = Path(self.pipedir, f"{block_name}.active")
        active.mkdir(mode=0o775, exist_ok=True)
        job_ids = []
        for batch in range((total + MAX_ARRAY_VAL - 1) // MAX_ARRAY_VAL):
            offset = batch * MAX_ARRAY_VAL
            count = min(MAX_ARRAY_VAL, total - offset)
            script = Path(self.pipedir, f"{block_name}.batch{batch + 1}.sh")
            stdout = f"{block_name}.o%j" if self.debug == "yes" else "/dev/null"
            stderr = f"{block_name}.e%j" if self.debug == "yes" else "/dev/null"
            debug = " debug" if self.debug == "yes" else ""
            script.write_text(
                "#!/bin/bash\n"
                f"#SBATCH --chdir={self.pipedir}\n#SBATCH --job-name={block_name}\n"
                f"#SBATCH --output={stdout}\n#SBATCH --error={stderr}\n"
                + (self.write_resource_string(qres) if qres else "")
                + f"#SBATCH --array=1-{count}\n#SBATCH --export=ALL\n"
                + f"export PYTHONPATH={MAIN_DIRECTORY}:${{PYTHONPATH:-}}\n"
                + f"task_id=$((SLURM_ARRAY_TASK_ID + {offset}))\n"
                + f"if ! {PYTHON} {HFPD_SCR / 'run_method.py'} {self.name} {self.gname} {sname} {self.pipedir}/{block_name} $task_id{debug}; then\n"
                + f"  gid=$(awk -v task=$task_id 'NR==task {{print $1}}' {self.pipedir}/{block_name})\n"
                + f"  touch {active}/FAIL.$gid\n  exit 1\nfi\n"
            )
            script.chmod(0o775)
            result = subprocess.run(["sbatch", str(script)], text=True, capture_output=True, check=True)
            print(result.stdout, end="", file=sys.stderr)
            match = re.search(r"Submitted batch job (\d+)", result.stdout)
            if not match:
                raise RuntimeError(f"Batch submission failed: {result.stdout}")
            job_ids.append(match.group(1))
        waiter = Path(self.pipedir, f"w{block_name}.sh")
        stdout = f"w{block_name}.o%j" if self.debug == "yes" else "/dev/null"
        stderr = f"w{block_name}.e%j" if self.debug == "yes" else "/dev/null"
        debug = " debug" if self.debug == "yes" else ""
        waiter.write_text(
            "#!/bin/bash\n"
            f"#SBATCH --chdir={self.pipedir}\n#SBATCH --job-name=w{block_name}_{self.gname}\n"
            f"#SBATCH --output={stdout}\n#SBATCH --error={stderr}\n"
            f"#SBATCH --dependency=afterany:{':'.join(job_ids)}\n#SBATCH --export=ALL\n"
            f"export PYTHONPATH={MAIN_DIRECTORY}:${{PYTHONPATH:-}}\n"
            f"{PYTHON} {HFPD_SCR / 'process_method.py'} {self.name} {self.gname} {sname} {block_name}{debug}\n"
        )
        waiter.chmod(0o775)
        result = subprocess.run(["sbatch", str(waiter)], text=True, capture_output=True, check=True)
        print(result.stdout, end="", file=sys.stderr)
        match = re.search(r"Submitted batch job (\d+)", result.stdout)
        if not match:
            raise RuntimeError(f"Waiter submission failed: {result.stdout}")
        return f"{block_name}\t{match.group(1)}"

    def status(self, gid, sname, jobstat):
        key, now = f"{gid}:{sname}", self.time()
        info = jobstat.get(key, "")
        info = re.sub(r"last checked:? [^)]+\)", f"last checked: {now})", info)
        if "last checked" not in info:
            info += f"(last checked: {now})"
        method = self.get_step_class(sname)(
            gname=self.gname,
            gid=gid,
            init="no",
            step_parameters=self.step_arg(sname),
        )
        durable_status = self.status_table.get(gid, sname).get("status")
        if method.complete() and durable_status == "completed":
            if "complete" not in info:
                info += f"({now} complete)"
            jobstat[key] = info
            return
        if "submit" in info and not any(word in info for word in ("fail", "complete")):
            match = re.search(r"submit ([^)]+\.tgt)\)", info)
            if match and Path(self.pipedir, match.group(1) + ".active").is_dir():
                jobstat[key] = info
                return
            jobstat[key] = info + f"({now} fail killed)"
            return
        for predecessor in [x for x in getattr(method, "holds", "").split(",") if x]:
            predecessor_info = jobstat.get(f"{gid}:{predecessor}", "")
            if any(word in predecessor_info for word in ("fail", "skipped")):
                jobstat[key] = info + f"({now} predecessor {predecessor} failed)"
                return
            if "complete" not in predecessor_info:
                if f"holding for {predecessor}" not in info:
                    info += f"({now} holding for {predecessor})"
                jobstat[key] = info
                return
        count = method.count_jobs()
        if count and Path(method.wrkdir, "done").exists() and Path(method.wrkdir, "process").exists():
            info += f"({now} fail output not found)"
        elif count == 0:
            info += f"({now} complete 0 jobs)"
        elif "ready" not in info:
            info += f"({now} ready {count} jobs)"
        method.prep()
        jobstat[key] = info

    def set_targets(self, targets):
        Path(self.pipedir, "targets.lst").write_text("\n".join(targets.split(",")) + "\n")

    def stage(self, message):
        Path(self.pipedir, f"{self.name}.stage").write_text(f"{message} ({self.time()}).\n")

    @staticmethod
    def time():
        now = time_module.localtime()
        return f"{['M','T','W','Th','F','S','Su'][now.tm_wday]}:{now.tm_hour}:{now.tm_min}:{now.tm_sec}"

    def mail(self):
        return None
