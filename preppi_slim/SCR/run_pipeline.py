#!/usr/bin/env python3
import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from MODS.Pipeline import Pipeline


def queued_count(path):
    return sum(1 for line in path.read_text().splitlines() if line.strip())


def slurm_active(job_id):
    result = subprocess.run(
        ["squeue", "-h", "-j", str(job_id)],
        text=True, capture_output=True, check=False,
    )
    return bool(result.stdout.strip())


def save_status(path, status):
    temporary = path.with_suffix(path.suffix + ".new")
    temporary.write_text("".join(f"{key}\t{value}\n" for key, value in sorted(status.items())))
    temporary.replace(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pipeline")
    parser.add_argument("genome")
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument("-m", "--maximum", type=int)
    args = parser.parse_args()
    pipeline = Pipeline(
        name=args.pipeline, gname=args.genome,
        debug="yes" if args.debug else "no",
    )
    os.chdir(pipeline.pipedir)
    steps = pipeline.steps()
    targets_file = Path("targets.lst")
    targets = (
        [line.strip() for line in targets_file.read_text().splitlines() if line.strip()]
        if targets_file.exists() else pipeline.genome.get_target_list()
    )
    pipeline.initialize_status(targets)
    status_path = Path(pipeline.pipedir, f"{pipeline.name}.jstat")
    status = {}
    for line in status_path.read_text().splitlines():
        if "\t" in line:
            key, info = line.split("\t", 1)
            status[key] = info
    pending = []
    reported_state = {
        f"{target}:{step}": "pending"
        for target in targets
        for step in steps
    }
    for target in targets:
        for step in steps:
            key = f"{target}:{step}"
            status.setdefault(key, f"({pipeline.time()} init)")
            if not re.search(r"fail|complete", status[key]):
                pending.append(key)
    if args.maximum is not None:
        pending = pending[:args.maximum]
    running_path = Path(pipeline.pipedir, "running")
    running = [line for line in running_path.read_text().splitlines() if line.strip()]
    pipeline.stage("Pipeline started.")
    started = time.time()

    while True:
        for key in list(pending):
            target, step = key.split(":", 1)
            pipeline.status(target, step, status)
            info = status[key]
            semantic_state, _ = pipeline.controller_state(info)
            if semantic_state != reported_state.get(key):
                pipeline.record_status(target, step, info)
                reported_state[key] = semantic_state
            if re.search(r"complete|skip|fail", info):
                pending.remove(key)
                continue
            match = re.search(r"ready (\d+) jobs", info)
            if match and "queued" not in info:
                status[key] += f"({pipeline.time()} queued)"
                pipeline.record_status(target, step, status[key])
                reported_state[key] = "queued"
                with open(Path(pipeline.pipedir, f"{step}.tgt"), "a") as handle:
                    handle.write(f"{target}\t{match.group(1)}\n")

        save_status(status_path, status)
        retained = []
        running_steps = set()
        for line in running:
            fields = line.split()
            if len(fields) < 2:
                continue
            block, job_id = fields[0], fields[1]
            if slurm_active(job_id):
                retained.append(line)
                running_steps.add(re.sub(r"_[A-Za-z0-9]{5}\.tgt$", "", block))
            else:
                # afterany normally removes this. If its postprocessor failed,
                # clear the stale marker so status() records a failure.
                import shutil
                shutil.rmtree(
                    Path(pipeline.pipedir, block + ".active"),
                    ignore_errors=True,
                )
        running = retained

        available = [
            step for step in steps
            if queued_count(Path(pipeline.pipedir, f"{step}.tgt"))
        ]
        for step in available:
            if len(running) >= 5:
                break
            if step in running_steps and len(available) > 1:
                continue
            record = pipeline.submit_block(step, status)
            if record:
                running.append(record)
                running_steps.add(step)
                save_status(status_path, status)
        running_path.write_text("\n".join(running) + ("\n" if running else ""))

        print(f"Remaining jobs: {len(pending)}", file=os.sys.stderr)
        if not pending and not running:
            failed = [key for key, info in status.items() if "fail" in info]
            save_status(status_path, status)
            if failed:
                pipeline.stage(f"Pipeline failed: {len(failed)} job(s) failed.")
                raise SystemExit(1)
            pipeline.stage("Pipeline complete.")
            pipeline.cleanup_transient_state()
            return
        pipeline.stage("Checking cpu/space usage and submitting jobs.")
        if time.time() - started > 10000:
            pipeline.qsub()
            return
        time.sleep(1)


if __name__ == "__main__":
    main()
