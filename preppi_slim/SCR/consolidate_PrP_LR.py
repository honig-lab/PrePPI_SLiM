#!/usr/bin/env python3

"""
Consolidate PrePPI-SLiM LR CSV files across batches or one genome directory.

USAGE EXAMPLES
--------------
# Single directory (no batches):
python consolidate_PrP_LR.py --base-dir human_AF_AS --lr-filename <filename> --output <full_file_path> --batch false --mode topk --topk 5

# Multiple batch directories:
python consolidate_PrP_LR.py --base-dir human_AF_AS --lr-filename <filename> --output <full_file_path> --batch true --mode max
"""

import argparse
import concurrent.futures
import gzip
import os
import glob
import time
from datetime import datetime
import numpy as np
import pandas as pd

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from MODS.Genome import target_ids, uniprot_mapping
from MODS.PipelineState import StatusTable, output_health


GENOME_DIR = os.environ.get(
    "HFPD_DATA_DIR", "/groups/bh6_gp/data/shares/databases/hfpd/genomes")


def now():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def env_int(name, default):
    try:
        return int(os.getenv(name, default))
    except (TypeError, ValueError):
        return default


def to_bool(s):
    """Convert CLI string to bool."""
    if isinstance(s, bool):
        return s
    s = str(s).strip().lower()
    if s in {"1", "true", "t", "yes", "y"}:
        return True
    if s in {"0", "false", "f", "no", "n"}:
        return False
    raise argparse.ArgumentTypeError(f"Invalid boolean value: {s}")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Consolidate PrePPI-SLiM LR CSV files across genome folders."
    )
    parser.add_argument("--base-dir", required=True,
                        help="Base directory name (e.g., human_AF_AS).")
    parser.add_argument("--batch", type=to_bool, required=True,
                        help="True to look for <base-dir>_batch*; False to process <base-dir> only.")
    parser.add_argument("--lr-filename", required=True,
                        help="Name of the per-sequence LR CSV under Seqs/<id>/Motifs/.")
    parser.add_argument("--output", required=True,
                        help="Output .csv.gz file (absolute path).")
    parser.add_argument("--mode", choices=["max", "topk"], default="topk",
                        help="Selection mode: 'max' or 'topk'.")
    parser.add_argument("--topk", type=int, default=5,
                        help="K for topk mode (ignored if --mode max).")
    parser.add_argument("--round", dest="round_dp", type=int, default=2,
                        help="Decimal places to round LR.")
    parser.add_argument("--chunksize", type=int, default=1_000_000,
                        help="Write chunk size.")
    parser.add_argument("--workers", type=int, default=None,
                        help="Number of parallel workers; defaults to min(SLURM_CPUS_PER_TASK, os.cpu_count()).")
    return parser.parse_args()


def process_lr_file(args):
    batch, hfpd_id, lr_filename = args
    file_path = os.path.join(batch, f"Seqs/{hfpd_id}/Motifs/{lr_filename}")
    if not os.path.exists(file_path):
        return None
    try:
        return pd.read_csv(file_path, comment="#", compression="infer",
                           dtype=str)
    except Exception as e:
        print(f"[{now()}] Error processing {hfpd_id}: {e}", flush=True)
        return None


def resolve_batch_dirs(base_dir, batch_flag):
    if batch_flag:
        pattern = os.path.join(GENOME_DIR, f"{base_dir}_batch*")
        dirs = sorted(glob.glob(pattern))
        if not dirs:
            print(f"[{now()}] WARNING: No batch directories found for pattern {pattern}", flush=True)
        else:
            print(f"[{now()}] Found {len(dirs)} batch directories under {GENOME_DIR}", flush=True)
        return dirs
    else:
        dir_path = os.path.join(GENOME_DIR, base_dir)
        if not os.path.isdir(dir_path):
            raise SystemExit(f"[{now()}] ERROR: Directory not found: {dir_path}")
        print(f"[{now()}] Using single directory: {dir_path}", flush=True)
        return [dir_path]


def build_map_dict(genome_names):
    mapping = {}
    for genome_name in sorted(genome_names):
        genome_home = os.path.join(GENOME_DIR, genome_name)
        try:
            genome_mapping = uniprot_mapping(genome_home)
        except (OSError, ValueError) as error:
            print(
                f"[{now()}] WARNING: Cannot read sequence metadata in "
                f"{genome_name}: {error}", flush=True,
            )
            continue
        for hfpd_id, uniprot_id in genome_mapping.items():
            mapping[(genome_name, hfpd_id)] = uniprot_id
    print(f"[{now()}] Built UniProt map | Entries={len(mapping):,}", flush=True)
    return mapping


def iter_all_dataframes(batch_dirs, lr_filename, workers):
    if workers is None:
        slurm_cpus = env_int("SLURM_CPUS_PER_TASK", 1)
        workers = min(slurm_cpus, os.cpu_count() or 1)
    print(f"[{now()}] Processing {len(batch_dirs)} batch dir(s) | workers={workers}", flush=True)

    with concurrent.futures.ProcessPoolExecutor(max_workers=workers) as executor:
        for batch in batch_dirs:
            t0 = time.time()
            try:
                ids = target_ids(batch)
            except (OSError, ValueError) as error:
                print(
                    f"[{now()}] WARNING: Cannot read sequence metadata in "
                    f"{os.path.basename(batch)}: {error}", flush=True,
                )
                continue
            jobs = [(batch, hfpd_id, lr_filename) for hfpd_id in ids]
            results = executor.map(process_lr_file, jobs)

            df_count = 0
            row_count = 0
            for df in results:
                if df is not None and len(df):
                    df_count += 1
                    row_count += len(df)
                    yield df
            dt = time.time() - t0
            print(f"[{now()}] {os.path.basename(batch)}: {df_count} files, {row_count:,} rows in {dt:.1f}s", flush=True)


def build_key(df):
    required = {"motif_genome", "motif_protein", "prd_genome", "prd_protein"}
    missing = required - set(df.columns)
    if missing:
        raise ValueError(f"LR CSV is missing role-specific columns: {sorted(missing)}")
    df["key"] = (
        df["motif_genome"] + ":" + df["motif_protein"] + "->" +
        df["prd_genome"] + ":" + df["prd_protein"]
    )
    df["likelihood_ratio"] = pd.to_numeric(df["likelihood_ratio"], errors="coerce")
    return df


def select_rows(df, mode, topk):
    if mode == "max":
        picked = df.loc[df.groupby("key")["likelihood_ratio"].idxmax()].copy()
        how = "max"
    else:
        picked = (df.sort_values("likelihood_ratio", ascending=False)
                    .groupby("key", group_keys=False, as_index=False)
                    .head(topk)
                    .copy())
        how = f"top{topk}"
    return picked, how


def consolidate(args):
    start_time = time.time()
    print(f"[{now()}] Start | base_dir={args.base_dir} | batch={args.batch}", flush=True)

    batch_dirs = resolve_batch_dirs(args.base_dir, args.batch)
    if not batch_dirs:
        raise SystemExit(f"[{now()}] ERROR: No batch directories found.")

    dfs = list(iter_all_dataframes(batch_dirs, args.lr_filename, args.workers))
    if not dfs:
        raise SystemExit(f"[{now()}] ERROR: No LR CSV rows found.")
    df_all = pd.concat(dfs, ignore_index=True)
    print(f"[{now()}] Loaded {len(df_all):,} total rows.", flush=True)

    df_all = build_key(df_all)
    df_sel, how = select_rows(df_all, args.mode, args.topk)
    print(f"[{now()}] Selected {how.upper()} | Kept {len(df_sel):,} rows.", flush=True)

    df_sel.sort_values(
        by=["motif_genome", "motif_protein", "prd_genome", "prd_protein"],
        inplace=True,
    )
    df_sel.drop(columns=["key"], inplace=True)

    genome_names = set(df_sel["motif_genome"]) | set(df_sel["prd_genome"])
    map_dict = build_map_dict(genome_names)
    df_sel["motif_protein_uniprot"] = [
        map_dict.get((genome_name, protein_id))
        for genome_name, protein_id in zip(df_sel["motif_genome"], df_sel["motif_protein"])
    ]
    df_sel["prd_protein_uniprot"] = [
        map_dict.get((genome_name, protein_id))
        for genome_name, protein_id in zip(df_sel["prd_genome"], df_sel["prd_protein"])
    ]

    n_before = len(df_sel)
    df_sel = df_sel[~np.isinf(df_sel["likelihood_ratio"])].copy()
    removed = n_before - len(df_sel)
    if removed:
        print(f"[{now()}] Removed {removed:,} rows with LR=inf", flush=True)

    df_sel["likelihood_ratio"] = df_sel["likelihood_ratio"].round(args.round_dp)

    preferred_columns = [
        "motif_genome", "motif_protein_uniprot", "motif_protein",
        "motif_start", "motif_end", "elm_class", "prd_genome",
        "prd_protein_uniprot", "prd_protein", "prd_name", "prd_start",
        "prd_end", "likelihood_ratio",
    ]
    existing_preferred = [
        column for column in preferred_columns if column in df_sel.columns
    ]
    remaining = [
        column for column in df_sel.columns if column not in existing_preferred
    ]
    df_sel = df_sel[existing_preferred + remaining]

    print(f"[{now()}] Writing to {args.output}...", flush=True)
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with gzip.open(args.output, "wt") as f_out:
        df_sel.to_csv(f_out, index=False, chunksize=args.chunksize)

    dt = time.time() - start_time
    mins, secs = divmod(dt, 60)
    print(f"[{now()}] Done | Wrote {len(df_sel):,} rows in {int(mins)} min {secs:.1f} s", flush=True)


def main():
    args = parse_args()
    genome_home = Path(GENOME_DIR, args.base_dir)
    status = StatusTable(
        genome_home / "Pipeline" / "ConsolidatePrPLR.pip" / "status.csv"
    )
    inspection = output_health([args.output])
    status.initialize([{
        "hfpd_id": args.base_dir,
        "subtask_id": "ConsolidatePrPLR",
        "work_directory": str(Path(args.output).parent),
        "status": "completed" if Path(args.output).is_file() else "pending",
        **inspection,
        "health": "healthy" if Path(args.output).is_file() else "pending",
    }])
    status.start(args.base_dir, "ConsolidatePrPLR", [args.output])
    started = time.perf_counter()
    try:
        consolidate(args)
    except BaseException as error:
        status.fail(
            args.base_dir,
            "ConsolidatePrPLR",
            elapsed_seconds=time.perf_counter() - started,
            expected_outputs=[args.output],
            error=f"{type(error).__name__}: {error}",
        )
        raise
    status.finish(
        args.base_dir,
        "ConsolidatePrPLR",
        elapsed_seconds=time.perf_counter() - started,
        expected_outputs=[args.output],
        message="Directional LR results consolidated and verified.",
    )
    status.remove_lock()

if __name__ == "__main__":
    main()

### Aakash
