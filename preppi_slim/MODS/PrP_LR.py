#!/usr/bin/env python3

"""Calculate PrePPI-SLiM likelihood ratios from per-anchor candidate CSV files."""

import argparse
import concurrent.futures
import csv
from functools import lru_cache
import gzip
import os
import sys
import tarfile

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from MODS.Genome import target_ids


PAIR_COLUMNS = [
    "motif_genome", "prd_genome", "anchor_genome", "anchor_protein",
    "anchor_role", "motif_protein", "prd_protein", "prd_name", "elm_class",
    "prd_start", "prd_end", "motif_sequence", "motif_start", "motif_end",
    "conserved", "disordered_fraction",
]

LEGACY_COLUMNS = [
    "motif_protein", "prd_protein", "elm_class", "prd_start", "prd_end",
    "motif_sequence", "motif_start", "motif_end", "conserved",
    "disordered_fraction",
]


def readBNs(bnNetFile, verbose=False):
    bnClass = {}
    bnCsv = {}
    bnDiso = {}
    lr_match = 1.0

    if verbose:
        sys.stdout.write(f"Reading Bayesian network file: {bnNetFile}\n")

    with open(bnNetFile, newline="") as csvfile:
        reader = csv.reader(csvfile)
        next(reader, None)
        first_row = next(reader, None)
        if first_row is not None:
            try:
                lr_match = float(first_row[6].strip()) if first_row[6].strip() else 0.0
            except (ValueError, IndexError):
                lr_match = 0.0
        for row in reader:
            if not row or len(row) < 8:
                continue
            clue = row[1].strip()
            try:
                lr_value = float(row[7].strip()) if row[7].strip() else 0.0
            except ValueError:
                lr_value = 0.0
            if clue.lower().startswith("diso"):
                bnDiso[clue.split("_")[-1]] = lr_value
            elif clue.lower().startswith("consv"):
                bnCsv[clue.split("_")[-1]] = lr_value
            else:
                bnClass[clue] = lr_value
    return lr_match, bnClass, bnCsv, bnDiso


def read_candidate_file(path, default_genome):
    """Read the new CSV.gz format or a legacy tabular tar.gz archive."""
    if path.endswith(".tar.gz"):
        frames = []
        with tarfile.open(path, "r:gz") as archive:
            for member in archive.getmembers():
                if (member.name.endswith("ProtPeptide_ELM.txt") and
                        not os.path.basename(member.name).startswith("._")):
                    handle = archive.extractfile(member)
                    if handle is None:
                        continue
                    try:
                        frame = pd.read_csv(
                            handle, header=None, names=LEGACY_COLUMNS, sep="\t",
                            dtype=str, comment="#",
                        )
                    except pd.errors.EmptyDataError:
                        continue
                    frames.append(frame)
        if not frames:
            return pd.DataFrame(columns=PAIR_COLUMNS)
        frame = pd.concat(frames, ignore_index=True)
        frame["motif_genome"] = default_genome
        frame["prd_genome"] = default_genome
        frame["anchor_genome"] = default_genome
        frame["anchor_protein"] = frame["motif_protein"]
        frame["anchor_role"] = "motif"
        frame["prd_name"] = ""
        return frame[PAIR_COLUMNS]

    try:
        frame = pd.read_csv(path, comment="#", dtype=str, compression="infer")
    except pd.errors.EmptyDataError:
        return pd.DataFrame(columns=PAIR_COLUMNS)
    # Candidate files produced before prd_name was added remain supported.
    if "prd_name" not in frame.columns:
        frame["prd_name"] = ""
    missing = set(PAIR_COLUMNS) - set(frame.columns)
    if missing:
        raise ValueError(f"candidate CSV is missing columns: {sorted(missing)}")
    return frame[PAIR_COLUMNS]


def directional_pair(row):
    """Identify one mechanistic motif-to-PRD direction."""
    return (
        str(row["motif_genome"]), str(row["motif_protein"]),
        str(row["prd_genome"]), str(row["prd_protein"]),
    )


def row_text(row, column):
    """Return a clean CSV field instead of rendering missing values as 'nan'."""
    value = row[column]
    return "" if pd.isna(value) else str(value).strip()


@lru_cache(maxsize=None)
def get_prd_name(genome, protein_id, prd_start, prd_end):
    """Find the Pfam HMM/domain name matching a PRD alignment range."""
    genome_dir = os.environ.get(
        "HFPD_DATA_DIR",
        "/groups/bh6_gp/data/shares/databases/hfpd/genomes",
    )
    pfam_path = os.path.join(
        genome_dir, genome, "Seqs", protein_id, "Motifs",
        f"{protein_id}.pfam",
    )
    try:
        with open(pfam_path, encoding="utf-8", errors="replace") as pfam_file:
            for line in pfam_file:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                fields = line.split()
                if len(fields) < 7:
                    continue
                if fields[1] == str(prd_start) and fields[2] == str(prd_end):
                    return fields[6]
    except OSError:
        return ""
    return ""


def open_text_output(path):
    if path.endswith(".gz"):
        return gzip.open(path, "wt", newline="")
    return open(path, "w", newline="")


def process_candidate_file(args):
    (batch, hfpd_id, input_filename, bnClass, bnCsv, bnDiso, lr_match,
     verbose, output_filename) = args
    input_path = os.path.join(batch, "Seqs", hfpd_id, "Motifs", input_filename)
    messages = []

    if not os.path.exists(input_path):
        return f"Warning: candidate file for {hfpd_id} not found: {input_path}\n"
    if verbose:
        messages.append(f"Processing candidate file: {input_path}\n")

    best = {}
    try:
        frame = read_candidate_file(input_path, os.path.basename(batch))
        for _, row in frame.iterrows():
            elm_class = str(row["elm_class"]).strip()
            conserved = str(row["conserved"]).strip()
            try:
                disorder = float(row["disordered_fraction"])
            except (TypeError, ValueError):
                disorder = 0.0
            disorder_bin = 1 if disorder >= 0.5 else 0
            lr_value = (
                lr_match
                * bnClass.get(elm_class, 0)
                * bnCsv.get(conserved, 0)
                * bnDiso.get(str(disorder_bin), bnDiso.get(disorder_bin, 0))
            )
            key = directional_pair(row)
            if key not in best or best[key][0] < lr_value:
                best[key] = (
                    lr_value, elm_class,
                    row_text(row, "motif_genome"),
                    row_text(row, "motif_protein"),
                    row_text(row, "motif_start"),
                    row_text(row, "motif_end"),
                    row_text(row, "prd_genome"),
                    row_text(row, "prd_protein"),
                    row_text(row, "prd_name"),
                    row_text(row, "prd_start"),
                    row_text(row, "prd_end"),
                )
    except Exception as error:
        return f"Error processing candidate file {input_path}: {error}\n"

    output_path = os.path.join(os.path.dirname(input_path), output_filename)
    try:
        with open_text_output(output_path) as output:
            output.write("# record_type=PrePPI-SLiM_likelihood_ratios\n")
            output.write(
                f"# source_genome_folder={os.path.basename(batch)}"
                f"\tquery_protein={hfpd_id}\tinput={input_filename}\n"
            )
            writer = csv.writer(output, lineterminator="\n")
            writer.writerow([
                "motif_genome", "motif_protein", "motif_start", "motif_end",
                "elm_class", "prd_genome", "prd_protein", "prd_name",
                "prd_start", "prd_end", "likelihood_ratio",
            ])
            for key in sorted(best):
                (
                    lr_value, elm_class, motif_genome, motif_id,
                    motif_start, motif_end, prd_genome, prd_id,
                    prd_name, prd_start, prd_end,
                ) = best[key]
                writer.writerow([
                    motif_genome, motif_id, motif_start, motif_end,
                    elm_class, prd_genome, prd_id, prd_name or get_prd_name(
                        prd_genome, prd_id, prd_start, prd_end),
                    prd_start, prd_end, lr_value,
                ])
        messages.append(f"Wrote output file: {output_path}\n")
    except Exception as error:
        messages.append(f"Error writing output file {output_path}: {error}\n")
    return "".join(messages)


def main():
    parser = argparse.ArgumentParser(
        description="Calculate PrePPI-SLiM likelihood ratios")
    parser.add_argument("-batch", required=True, help="Genome/batch directory")
    parser.add_argument("-g", required=True, help="Anchor genome basename")
    parser.add_argument("-i", "--input-filename", required=True,
                        help="Per-protein candidate CSV.gz filename")
    parser.add_argument("-b", required=True, help="Bayesian-network CSV file")
    parser.add_argument("-o", required=True, help="Per-protein LR CSV filename")
    parser.add_argument("-v", action="store_true", help="Verbose mode")
    parser.add_argument("-d", action="store_true", help="Debug/verbose mode")
    args = parser.parse_args()

    verbose = args.v or args.d
    batch = args.batch
    sys.stdout.write(f"Processing batch directory: {batch}\n")
    try:
        map_list = sorted(set(target_ids(batch)))
    except Exception as error:
        raise SystemExit(f"Error reading genome sequences from {batch}: {error}") from error
    if not map_list:
        raise SystemExit(f"No protein targets found in {batch}")

    lr_match, bnClass, bnCsv, bnDiso = readBNs(args.b, verbose=verbose)
    tasks = [
        (batch, hfpd_id, args.input_filename, bnClass, bnCsv, bnDiso,
         lr_match, verbose, args.o)
        for hfpd_id in map_list
    ]
    with concurrent.futures.ProcessPoolExecutor(max_workers=16) as executor:
        for result in executor.map(process_candidate_file, tasks):
            sys.stdout.write(result)
    sys.stdout.write(f"Processing completed for batch: {batch}\n")


if __name__ == "__main__":
    main()
