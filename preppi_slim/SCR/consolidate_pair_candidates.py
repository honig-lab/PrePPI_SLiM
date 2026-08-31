#!/usr/bin/env python3

"""Convert two legacy directional PrePPI-SLiM tar archives to one CSV.gz."""

import argparse
import csv
import gzip
import os
import tarfile
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from MODS.Genome import target_ids


LEGACY_COLUMNS = [
    "motif_protein", "prd_protein", "elm_class", "prd_start", "prd_end",
    "motif_sequence", "motif_start", "motif_end", "conserved",
    "disordered_fraction",
]

OUTPUT_COLUMNS = [
    "motif_genome", "prd_genome", "anchor_genome", "anchor_protein",
    "anchor_role", "motif_protein", "prd_protein", "prd_name",
    *LEGACY_COLUMNS[2:],
]


def safe_name(value):
    return "".join(character if character.isalnum() or character in "_.-" else "_"
                   for character in value)


def read_legacy_archive(path, default_motif_genome, default_prd_genome,
                        anchor_genome, anchor_protein, default_anchor_role):
    rows = []
    metadata = {}
    with tarfile.open(path, "r:gz") as archive:
        for member in archive.getmembers():
            if (not member.isfile() or
                    not member.name.endswith("ProtPeptide_ELM.txt") or
                    os.path.basename(member.name).startswith("._")):
                continue
            handle = archive.extractfile(member)
            if handle is None:
                continue
            for raw_line in handle:
                line = raw_line.decode("utf-8").strip()
                if not line:
                    continue
                if line.startswith("#"):
                    content = line[1:].strip()
                    for item in content.split("\t"):
                        if "=" in item:
                            key, value = item.split("=", 1)
                            metadata[key.strip()] = value.strip()
                    continue
                fields = line.split("\t")
                if len(fields) != len(LEGACY_COLUMNS):
                    raise ValueError(
                        f"{path}: expected {len(LEGACY_COLUMNS)} columns, found {len(fields)}")
                motif_genome = metadata.get("motif_genome", default_motif_genome)
                prd_genome = metadata.get("prd_genome", default_prd_genome)
                anchor_role = metadata.get("anchor_role", default_anchor_role)
                motif_protein, prd_protein, *remaining = fields
                rows.append([
                    motif_genome, prd_genome, anchor_genome, anchor_protein,
                    anchor_role, motif_protein, prd_protein, "", *remaining,
                ])
    return rows


def main():
    parser = argparse.ArgumentParser(
        description="Combine legacy directional pair archives into CSV.gz")
    parser.add_argument("--genome", required=True, help="Anchor genome (genome1)")
    parser.add_argument("--genome2", required=True, help="Partner genome")
    parser.add_argument(
        "--genome-dir",
        default=os.environ.get(
            "HFPD_DATA_DIR", "/groups/bh6_gp/data/shares/databases/hfpd/genomes"),
        help="Root containing genome folders",
    )
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()

    genome_home = os.path.join(args.genome_dir, args.genome)
    try:
        targets = target_ids(genome_home)
    except (OSError, ValueError) as error:
        raise SystemExit(
            f"Cannot read genome sequences from {genome_home}: {error}"
        ) from error
    if not targets:
        raise SystemExit(f"No protein targets found in {genome_home}")

    forward_name = safe_name(
        f"{args.genome}_slim_{args.genome2}_prd_ProtPeptide_ELM.txt.tar.gz")
    reverse_name = safe_name(
        f"{args.genome2}_slim_{args.genome}_prd_ProtPeptide_ELM.txt.tar.gz")
    output_name = safe_name(
        f"{args.genome}_vs_{args.genome2}_prd_slim_candidates.csv.gz")

    converted = skipped = missing = 0
    for target in targets:
        motif_dir = os.path.join(genome_home, "Seqs", target, "Motifs")
        output_path = os.path.join(motif_dir, output_name)
        if os.path.exists(output_path) and not args.overwrite:
            skipped += 1
            continue
        forward_path = os.path.join(motif_dir, forward_name)
        reverse_path = os.path.join(motif_dir, reverse_name)
        if not os.path.exists(forward_path) and not os.path.exists(reverse_path):
            missing += 1
            continue

        rows = []
        if os.path.exists(forward_path):
            rows.extend(read_legacy_archive(
                forward_path, args.genome, args.genome2,
                args.genome, target, "motif"))
        if os.path.exists(reverse_path):
            rows.extend(read_legacy_archive(
                reverse_path, args.genome2, args.genome,
                args.genome, target, "prd"))

        with gzip.open(output_path, "wt", newline="") as output:
            output.write("# record_type=PrePPI-SLiM_PRD-SLiM_candidates\n")
            output.write(
                f"# anchor_genome={args.genome}\tpartner_genome={args.genome2}"
                "\torientation=both\n")
            writer = csv.writer(output, lineterminator="\n")
            writer.writerow(OUTPUT_COLUMNS)
            writer.writerows(sorted(rows))
        converted += 1

    print(f"Output filename: {output_name}")
    print(f"Converted: {converted}; already present: {skipped}; no source archives: {missing}")


if __name__ == "__main__":
    main()
