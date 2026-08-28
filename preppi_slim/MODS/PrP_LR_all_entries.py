#!/usr/bin/env python3

"""Calculate and retain every PrePPI-SLiM candidate likelihood ratio."""

import argparse
import concurrent.futures
import csv
import os
import sys

import pandas as pd

from PrP_LR import (
    get_prd_name,
    open_text_output,
    readBNs,
    read_candidate_file,
    row_text,
)


def process_candidate_file(args):
    (batch, hfpd_id, input_filename, bnClass, bnCsv, bnDiso, lr_match,
     verbose, output_filename) = args
    input_path = os.path.join(batch, "Seqs", hfpd_id, "Motifs", input_filename)
    if not os.path.exists(input_path):
        return f"Warning: candidate file for {hfpd_id} not found: {input_path}\n"

    try:
        frame = read_candidate_file(input_path, os.path.basename(batch))
    except Exception as error:
        return f"Error processing candidate file {input_path}: {error}\n"

    output_path = os.path.join(os.path.dirname(input_path), output_filename)
    try:
        with open_text_output(output_path) as output:
            output.write("# record_type=PrePPI-SLiM_likelihood_ratios_all_entries\n")
            output.write(
                f"# source_genome_folder={os.path.basename(batch)}"
                f"\tquery_protein={hfpd_id}\tinput={input_filename}\n"
            )
            writer = csv.writer(output, lineterminator="\n")
            writer.writerow([
                "motif_genome", "motif_protein", "motif_start", "motif_end",
                "prd_genome", "prd_protein", "prd_name",
                "prd_start", "prd_end", "likelihood_ratio", "elm_class",
                "anchor_role",
            ])
            rows = []
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
                motif_genome = row_text(row, "motif_genome")
                motif_protein = row_text(row, "motif_protein")
                prd_genome = row_text(row, "prd_genome")
                prd_protein = row_text(row, "prd_protein")
                prd_start = row_text(row, "prd_start")
                prd_end = row_text(row, "prd_end")
                prd_name = row_text(row, "prd_name") or get_prd_name(
                    prd_genome, prd_protein, prd_start, prd_end)
                rows.append([
                    motif_genome, motif_protein,
                    row_text(row, "motif_start"), row_text(row, "motif_end"),
                    prd_genome, prd_protein, prd_name, prd_start, prd_end,
                    lr_value, elm_class, row_text(row, "anchor_role"),
                ])
            writer.writerows(sorted(rows, key=lambda item: -float(item[9])))
    except Exception as error:
        return f"Error writing output file {output_path}: {error}\n"
    return f"Wrote output file: {output_path}\n" if verbose else ""


def main():
    parser = argparse.ArgumentParser(
        description="Calculate all PrePPI-SLiM candidate likelihood ratios")
    parser.add_argument("-batch", required=True, help="Genome/batch directory")
    parser.add_argument("-g", required=True, help="Anchor genome basename")
    parser.add_argument("-i", "--input-filename", required=True)
    parser.add_argument("-b", required=True, help="Bayesian-network CSV file")
    parser.add_argument("-o", required=True, help="Per-protein LR CSV filename")
    parser.add_argument("-v", action="store_true")
    parser.add_argument("-d", action="store_true")
    args = parser.parse_args()

    map_list_file = os.path.join(args.batch, "fasta", "map_list")
    try:
        targets = sorted(set(pd.read_csv(
            map_list_file, header=None, sep="\t", dtype=str,
        )[0].to_list()))
    except Exception as error:
        raise SystemExit(f"Error reading {map_list_file}: {error}") from error

    lr_match, bnClass, bnCsv, bnDiso = readBNs(args.b, verbose=args.v or args.d)
    tasks = [
        (args.batch, target, args.input_filename, bnClass, bnCsv, bnDiso,
         lr_match, args.v or args.d, args.o)
        for target in targets
    ]
    with concurrent.futures.ProcessPoolExecutor(max_workers=16) as executor:
        for result in executor.map(process_candidate_file, tasks):
            sys.stdout.write(result)


if __name__ == "__main__":
    main()
