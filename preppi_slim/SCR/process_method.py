#!/usr/bin/env python3
import argparse
import os
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from MODS.Pipeline import Pipeline


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pipeline")
    parser.add_argument("genome")
    parser.add_argument("step")
    parser.add_argument("targets")
    parser.add_argument("debug", nargs="?")
    args = parser.parse_args()
    pipeline = Pipeline(name=args.pipeline, gname=args.genome)
    target_file = Path(pipeline.pipedir, Path(args.targets).name)
    active = Path(str(target_file) + ".active")
    failures = list(active.glob("FAIL.*"))
    if failures:
        shutil.rmtree(active, ignore_errors=True)
        raise SystemExit(f"{len(failures)} method task(s) failed in {target_file.name}")
    for line in target_file.read_text().splitlines():
        if not line.strip():
            continue
        target = line.split()[0]
        method = pipeline.get_step_class(args.step)(
            gname=args.genome, gid=target,
            step_parameters=pipeline.step_arg(args.step),
        )
        os.chdir(method.wrkdir)
        method.process()
        Path(method.wrkdir, "process").touch()
    for path in Path(pipeline.pipedir).glob(target_file.name + "*"):
        if path == active or "time" in path.name:
            continue
        if path.is_file():
            shutil.move(str(path), str(Path(pipeline.pipedir, "completed", path.name)))
    shutil.rmtree(active, ignore_errors=True)


if __name__ == "__main__":
    main()
