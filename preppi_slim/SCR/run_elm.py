#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from MODS.Pipeline import Pipeline


def main():
    parser = argparse.ArgumentParser(description="Run PrePPI-SLiM annotation")
    parser.add_argument("genome")
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument("-q", "--no-submit", action="store_true")
    parser.add_argument("-t", "--targets")
    args = parser.parse_args()
    pipeline = Pipeline(name="run_elm", gname=args.genome, debug="yes" if args.debug else "no")
    Path(pipeline.stepsfn).unlink(missing_ok=True)
    Path(pipeline.stepsfn + ".focus").unlink(missing_ok=True)
    if args.targets:
        pipeline.set_targets(args.targets)
    for step in ("FindMotifs_ELM", "FindPRDs_ELM", "Gopher", "MuscleG", "MotifConsv"):
        pipeline.add_step(step)
    pipeline.qsub("no" if args.no_submit else "yes")


if __name__ == "__main__":
    main()
