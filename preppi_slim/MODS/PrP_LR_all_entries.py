#!/usr/bin/env python3

"""Calculate and retain every PrePPI-SLiM candidate likelihood ratio."""

import argparse
import concurrent.futures
import csv
import os
from pathlib import Path
import shutil
import sys
import time

import pandas as pd

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from MODS.Genome import target_ids
from MODS.PipelineState import StatusTable, output_health

from PrP_LR import (
    get_prd_name,
    open_text_output,
    readBNs,
    read_candidate_file,
    row_text,
)


def process_candidate_file(args):
    (batch, hfpd_id, input_filename, bnClass, bnCsv, bnDiso, lr_match,
     verbose, output_filename, status_path) = args
    input_path = os.path.join(batch, "Seqs", hfpd_id, "Motifs", input_filename)
    output_path = os.path.join(os.path.dirname(input_path), output_filename)
    status = StatusTable(status_path)
    status.start(hfpd_id, "PrP_LR_all_entries", [output_path])
    started = time.perf_counter()
    if not os.path.exists(input_path):
        message = f"Candidate file for {hfpd_id} not found: {input_path}"
        status.fail(
            hfpd_id, "PrP_LR_all_entries",
            elapsed_seconds=time.perf_counter() - started,
            expected_outputs=[output_path], error=message,
        )
        return f"Error: {message}\n"

    try:
        frame = read_candidate_file(input_path, os.path.basename(batch))
    except Exception as error:
        message = f"Error processing candidate file {input_path}: {error}"
        status.fail(
            hfpd_id, "PrP_LR_all_entries",
            elapsed_seconds=time.perf_counter() - started,
            expected_outputs=[output_path], error=message,
        )
        return message + "\n"

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
                "elm_class", "prd_genome", "prd_protein", "prd_name",
                "prd_start", "prd_end", "likelihood_ratio",
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
                    elm_class, prd_genome, prd_protein, prd_name,
                    prd_start, prd_end, lr_value, row_text(row, "anchor_role"),
                ])
            writer.writerows(sorted(rows, key=lambda item: -float(item[10])))
    except Exception as error:
        message = f"Error writing output file {output_path}: {error}"
        status.fail(
            hfpd_id, "PrP_LR_all_entries",
            elapsed_seconds=time.perf_counter() - started,
            expected_outputs=[output_path], error=message,
        )
        return message + "\n"
    status.finish(
        hfpd_id, "PrP_LR_all_entries",
        elapsed_seconds=time.perf_counter() - started,
        expected_outputs=[output_path], message="LR output written and verified.",
    )
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

    try:
        targets = sorted(set(target_ids(args.batch)))
    except Exception as error:
        raise SystemExit(
            f"Error reading genome sequences from {args.batch}: {error}"
        ) from error
    if not targets:
        raise SystemExit(f"No protein targets found in {args.batch}")

    pipeline_dir = Path(args.batch, "Pipeline", "PrP_LR_all_entries.pip")
    status_path = pipeline_dir / "status.csv"
    status = StatusTable(status_path)
    rows = []
    for target in targets:
        output = Path(args.batch, "Seqs", target, "Motifs", args.o)
        inspection = output_health([output])
        rows.append({
            "hfpd_id": target,
            "subtask_id": "PrP_LR_all_entries",
            "work_directory": str(output.parent),
            "status": "completed" if output.is_file() else "pending",
            **inspection,
            "health": "healthy" if output.is_file() else "pending",
        })
    status.initialize(rows)

    pending = [
        target for target in targets
        if status.get(target, "PrP_LR_all_entries").get("status")
        not in {"completed", "skipped"}
    ]

    lr_match, bnClass, bnCsv, bnDiso = readBNs(args.b, verbose=args.v or args.d)
    tasks = [
        (args.batch, target, args.input_filename, bnClass, bnCsv, bnDiso,
         lr_match, args.v or args.d, args.o, str(status_path))
        for target in pending
    ]
    failed = 0
    if tasks:
        with concurrent.futures.ProcessPoolExecutor(max_workers=16) as executor:
            for result in executor.map(process_candidate_file, tasks):
                sys.stdout.write(result)
                failed += int(result.startswith("Error"))
    if failed:
        raise SystemExit(f"LR calculation failed for {failed} protein(s)")
    if not (args.v or args.d) and status.all_terminal_and_healthy():
        for child in pipeline_dir.iterdir():
            if child.name in {"status.csv", "status.csv.lock"}:
                continue
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink(missing_ok=True)
        status.remove_lock()


if __name__ == "__main__":
    main()
