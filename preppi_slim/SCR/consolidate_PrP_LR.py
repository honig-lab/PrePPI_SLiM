#!/usr/bin/env python3

"""
Consolidate ProtPeptide ELM .lr files across HFPD batches or a single directory.

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


# --------------------------- CONSTANT PATH --------------------------- #
GENOME_DIR = "/groups/bh6_gp/data/shares/databases/hfpd/genomes/"
# --------------------------------------------------------------------- #


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
        description="Consolidate ProtPeptide ELM .lr files across HFPD batches or a single directory."
    )
    parser.add_argument("--base-dir", required=True,
                        help="Base directory name (e.g., human_AF_AS).")
    parser.add_argument("--batch", type=to_bool, required=True,
                        help="True to look for <base-dir>_batch*; False to process <base-dir> only.")
    parser.add_argument("--lr-filename", required=True,
                        help="Name of the per-sequence .lr file under Seqs/<id>/Motifs/.")
    parser.add_argument("--output", required=True,
                        help="Output .gz TSV file (absolute path).")
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
        return pd.read_csv(file_path, header=None, sep="\t",
                           dtype={0: str, 1: str, 2: float, 3: str})
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


def build_map_dict_from_batches(batch_dirs):
    frames = []
    for b in batch_dirs:
        map_path = os.path.join(b, "fasta/map_list")
        if not os.path.exists(map_path):
            print(f"[{now()}] WARNING: Missing map_list in {os.path.basename(b)}", flush=True)
            continue
        df = pd.read_csv(map_path, sep="\t", header=None, dtype=str, names=["HFPD_ID", "UniProt_ID"])
        frames.append(df)
    if not frames:
        raise SystemExit(f"[{now()}] ERROR: No map_list files found.")
    df = pd.concat(frames, ignore_index=True).dropna()
    df["UniProt_ID"] = df["UniProt_ID"].str.lstrip(">")
    df = df.drop_duplicates(subset=["HFPD_ID"], keep="first")
    print(f"[{now()}] Built UniProt map | Unique IDs={df['HFPD_ID'].nunique():,}", flush=True)
    return df.set_index("HFPD_ID")["UniProt_ID"].to_dict()


def iter_all_dataframes(batch_dirs, lr_filename, workers):
    if workers is None:
        slurm_cpus = env_int("SLURM_CPUS_PER_TASK", 1)
        workers = min(slurm_cpus, os.cpu_count() or 1)
    print(f"[{now()}] Processing {len(batch_dirs)} batch dir(s) | workers={workers}", flush=True)

    with concurrent.futures.ProcessPoolExecutor(max_workers=workers) as executor:
        for batch in batch_dirs:
            t0 = time.time()
            map_list_path = os.path.join(batch, "fasta/map_list")
            if not os.path.exists(map_list_path):
                print(f"[{now()}] WARNING: Missing map_list in {os.path.basename(batch)}", flush=True)
                continue

            ids = pd.read_csv(map_list_path, header=None, sep="\t", dtype=str)[0].unique()
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
    id1 = df.iloc[:, 0].values
    id2 = df.iloc[:, 1].values
    df["key"] = np.where(id1 < id2, id1 + "_" + id2, id2 + "_" + id1)
    return df


def select_rows(df, mode, topk):
    if mode == "max":
        picked = df.loc[df.groupby("key")[2].idxmax()].copy()
        how = "max"
    else:
        picked = (df.sort_values(2, ascending=False)
                    .groupby("key", group_keys=False, as_index=False)
                    .head(topk)
                    .copy())
        how = f"top{topk}"
    return picked, how


def main():
    args = parse_args()
    start_time = time.time()
    print(f"[{now()}] Start | base_dir={args.base_dir} | batch={args.batch}", flush=True)

    batch_dirs = resolve_batch_dirs(args.base_dir, args.batch)
    if not batch_dirs:
        raise SystemExit(f"[{now()}] ERROR: No batch directories found.")

    dfs = list(iter_all_dataframes(batch_dirs, args.lr_filename, args.workers))
    if not dfs:
        raise SystemExit(f"[{now()}] ERROR: No .lr rows found.")
    df_all = pd.concat(dfs, ignore_index=True)
    print(f"[{now()}] Loaded {len(df_all):,} total rows.", flush=True)

    df_all = build_key(df_all)
    df_sel, how = select_rows(df_all, args.mode, args.topk)
    print(f"[{now()}] Selected {how.upper()} | Kept {len(df_sel):,} rows.", flush=True)

    df_sel.sort_values(by=[0, 1], key=lambda s: s.astype(int), inplace=True)
    df_sel.drop(columns=["key"], inplace=True)

    map_dict = build_map_dict_from_batches(batch_dirs)
    df_sel["UniProt_ID1"] = df_sel.iloc[:, 0].map(map_dict)
    df_sel["UniProt_ID2"] = df_sel.iloc[:, 1].map(map_dict)

    df_sel = df_sel[["UniProt_ID1", "UniProt_ID2", 0, 1, 2, 3]]
    df_sel = df_sel.rename(columns={0: "HFPD_ID1", 1: "HFPD_ID2", 2: "LR", 3: "ELM_Class"})

    n_before = len(df_sel)
    df_sel = df_sel[~np.isinf(df_sel["LR"])].copy()
    removed = n_before - len(df_sel)
    if removed:
        print(f"[{now()}] Removed {removed:,} rows with LR=inf", flush=True)

    df_sel["LR"] = df_sel["LR"].round(args.round_dp)

    print(f"[{now()}] Writing to {args.output}...", flush=True)
    os.makedirs(os.path.dirname(args.output), exist_ok=True)
    with gzip.open(args.output, "wt") as f_out:
        df_sel.to_csv(f_out, sep="\t", index=False, chunksize=args.chunksize)

    dt = time.time() - start_time
    mins, secs = divmod(dt, 60)
    print(f"[{now()}] Done | Wrote {len(df_sel):,} rows in {int(mins)} min {secs:.1f} s", flush=True)

if __name__ == "__main__":
    main()

### Aakash
