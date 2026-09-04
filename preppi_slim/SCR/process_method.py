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
    pipeline = Pipeline(
        name=args.pipeline,
        gname=args.genome,
        debug="yes" if args.debug else "no",
    )
    target_file = Path(pipeline.pipedir, Path(args.targets).name)
    active = Path(str(target_file) + ".active")
    failures = list(active.glob("FAIL.*"))
    failed_targets = {path.name.removeprefix("FAIL.") for path in failures}
    for line in target_file.read_text().splitlines():
        if not line.strip():
            continue
        target = line.split()[0]
        if target in failed_targets:
            continue
        method = pipeline.get_step_class(args.step)(
            gname=args.genome, gid=target,
            step_parameters=pipeline.step_arg(args.step),
        )
        os.chdir(method.wrkdir)
        outputs = pipeline.method_outputs(method)
        try:
            method.process()
            Path(method.wrkdir, "process").touch()
            if not method.complete():
                raise RuntimeError("Post-processing completed but output is missing")
            if not args.debug:
                shutil.rmtree(method.wrkdir, ignore_errors=True)
            pipeline.status_table.finish(
                target,
                args.step,
                expected_outputs=outputs,
                message="Output verified and temporary workspace removed.",
            )
        except BaseException as error:
            pipeline.status_table.fail(
                target,
                args.step,
                expected_outputs=outputs,
                error=f"{type(error).__name__}: {error}",
            )
            raise
    for path in Path(pipeline.pipedir).glob(target_file.name + "*"):
        if path == active or "time" in path.name:
            continue
        if path.is_file() and args.debug:
            shutil.move(str(path), str(Path(pipeline.pipedir, "completed", path.name)))
        elif path.is_file():
            path.unlink()
    shutil.rmtree(active, ignore_errors=True)
    if failures:
        raise SystemExit(
            f"{len(failures)} method task(s) failed in {target_file.name}"
        )


if __name__ == "__main__":
    main()
