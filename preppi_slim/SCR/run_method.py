#!/usr/bin/env python3
import argparse
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from MODS.Pipeline import Pipeline


def task_record(path, task_id):
    cumulative = 0
    for line in Path(path).read_text().splitlines():
        if not line.strip():
            continue
        target, count_text = line.split()
        count = int(count_text)
        if task_id <= cumulative + count:
            return target, task_id - cumulative
        cumulative += count
    raise ValueError(f"Task {task_id} is outside target list {path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pipeline")
    parser.add_argument("genome")
    parser.add_argument("step")
    parser.add_argument("targets")
    parser.add_argument("task_id", type=int)
    parser.add_argument("debug", nargs="?")
    args = parser.parse_args()
    pipeline = Pipeline(name=args.pipeline, gname=args.genome)
    target_file = Path(args.targets).resolve()
    target, method_task = task_record(target_file, args.task_id)
    method = pipeline.get_step_class(args.step)(
        gname=args.genome, gid=target, step_parameters=pipeline.step_arg(args.step)
    )
    if hasattr(method, "sge_input"):
        method.sge_task_id = method_task
    if args.debug:
        method.quiet = "no"
        method.debug = "yes"
    active = Path(str(target_file) + ".active")
    run_marker = active / f"RUN.{target}.{method_task}"
    if active.is_dir():
        run_marker.touch()
    os.chdir(method.wrkdir)
    started = time.time()
    method.run()
    elapsed = int(time.time() - started)
    Path(method.wrkdir, "done").write_text(pipeline.time() + "\n")
    if active.is_dir():
        (active / f"FREE.{target}.{method_task}").touch()
        (active / f"TM.{target}.{method_task}").write_text(
            f"{target}\t{method_task}\t{elapsed}\t{method.count_tasks()}\n"
        )


if __name__ == "__main__":
    main()
