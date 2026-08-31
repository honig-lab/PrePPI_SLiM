#!/usr/bin/env python3
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from MODS.Genome import Genome
from MODS.Pipeline import Pipeline


def main():
    parser = argparse.ArgumentParser(description="Enumerate directional PRD-SLiM candidates")
    parser.add_argument("genome1")
    parser.add_argument("-g", "--genome2")
    parser.add_argument("-O", "--orientation", choices=("motif", "prd", "both"), default="both")
    parser.add_argument("-r", "--reverse", action="store_true")
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument("-q", "--no-submit", action="store_true")
    args = parser.parse_args()
    genome2 = args.genome2 or args.genome1
    orientation = "prd" if args.reverse else args.orientation
    for genome in (args.genome1, genome2):
        obj = Genome(gname=genome)
        if not Path(obj.home).is_dir():
            raise SystemExit(f"Genome does not exist: {obj.home}")
    safe_partner = re.sub(r"[^A-Za-z0-9_.-]+", "_", genome2)
    run_tag = f"{orientation}_{safe_partner}"
    name = f"ProtPeptide_ELM_{run_tag}"
    pipeline = Pipeline(name=name, gname=args.genome1, debug="yes" if args.debug else "no")
    Path(pipeline.stepsfn).unlink(missing_ok=True)
    Path(pipeline.stepsfn + ".focus").unlink(missing_ok=True)
    pipeline.add_step(
        "ProtPeptide_ELM", external=genome2,
        orientation=orientation, run_tag=run_tag,
    )
    pipeline.qsub("no" if args.no_submit else "yes")


if __name__ == "__main__":
    main()
