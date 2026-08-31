#!/usr/bin/env python3
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from MODS.Genome import Genome
from MODS.Pipeline import Pipeline


def main():
    parser = argparse.ArgumentParser(description="Create a SLiM genome and run IUPred")
    parser.add_argument("genome")
    parser.add_argument("-f", "--fasta", required=True)
    parser.add_argument("-d", "--debug", action="store_true")
    parser.add_argument("-q", "--no-submit", action="store_true")
    args = parser.parse_args()
    Genome(gname=args.genome).init(args.fasta)
    pipeline = Pipeline(name="Setup", gname=args.genome, debug="yes" if args.debug else "no")
    Path(pipeline.stepsfn).unlink(missing_ok=True)
    Path(pipeline.stepsfn + ".focus").unlink(missing_ok=True)
    pipeline.add_step("IUPRED")
    pipeline.qsub("no" if args.no_submit else "yes")


if __name__ == "__main__":
    main()
