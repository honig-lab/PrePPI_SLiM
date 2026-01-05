#!/usr/bin/env python3

"""
Module: PrP_LR_all_entries.py

This module processes a single batch directory for PrePPI scores (ELM version).
It reads the Bayesian network CSV file, processes all hfpd_ids found in the batch's
fasta/map_list file in parallel (using 16 processors), and writes an output file
(ProtPeptide_ELM.lr) in the same directory as each input tar file.

Usage:
    python PrP_LR_all_entries.py -batch <batch_directory> -g <genome> -b <BN_file> -o <output_file> [-v] [-d]

Arguments:
  -batch    Path to the batch directory (e.g., /groups/bh6_gp/data/shares/databases/hfpd/genomes/human_AF_AS_batch1)
  -g        Genome basename (e.g., human_AF_AS)
  -b        Path to the Bayesian network CSV file
  -o        Output file name (e.g., ProtPeptide_ELM_001.lr)
  -v        Verbose mode
  -d        Debug mode (implies verbose)
"""

import os
import sys
import argparse
import time
import csv
import tarfile
import pandas as pd
from collections import defaultdict
import concurrent.futures

def readBNs(bnNetFile, verbose=False):
    """
    Reads the Bayesian network CSV file and returns:
      - lr_match: LR value from the first (match) row (column index 6)
      - bnClass: dictionary for clues that do not start with 'diso' or 'consv'
      - bnCsv:   dictionary for conservation scores (clues starting with 'consv'),
                 keyed by the digit (e.g., '0' or '1')
      - bnDiso:  dictionary for disorder scores (clues starting with 'diso'),
                 keyed by the digit (e.g., '0' or '1')

    The CSV file is expected to have a header. The first data row is assumed to be
    the "match" row, whose column 6 is used as lr_match. For subsequent rows, the LR
    value is taken from the last column (column index 7). Non-numeric or empty values
    are converted to 0.0.
    """
    bnClass = {}
    bnCsv = {}
    bnDiso = {}
    lr_match = 1.0

    if verbose:
        sys.stdout.write(f"Reading Bayesian network file: {bnNetFile}\n")
    
    with open(bnNetFile, newline='') as csvfile:
        reader = csv.reader(csvfile)
        header = next(reader, None)  # Skip header
        first_row = next(reader, None)  # First data row assumed to be "match"
        if first_row is not None:
            try:
                lr_match = float(first_row[6].strip()) if first_row[6].strip() != "" else 0.0
            except (ValueError, IndexError):
                lr_match = 0.0
        for row in reader:
            if not row or len(row) < 8:
                continue
            clue = row[1].strip()
            lr_val = row[7].strip()  # Use last column for LR value
            try:
                lr_value = float(lr_val) if lr_val != "" else 0.0
            except ValueError:
                lr_value = 0.0
            if clue.lower().startswith("diso"):
                parts = clue.split('_')
                key = parts[-1] if len(parts) > 1 else clue
                bnDiso[key] = lr_value
            elif clue.lower().startswith("consv"):
                parts = clue.split('_')
                key = parts[-1] if len(parts) > 1 else clue
                bnCsv[key] = lr_value
            else:
                bnClass[clue] = lr_value
    return lr_match, bnClass, bnCsv, bnDiso

def process_tar_file(args):
    """
    Process a single tar file for a given hfpd_id in the batch.

    Args (passed as a tuple):
      batch             : Path to the batch directory.
      hfpd_id           : Current hfpd identifier (string).
      bnClass           : Dictionary for ELM classes.
      bnCsv             : Dictionary for conservation scores.
      bnDiso            : Dictionary for disorder scores.
      lr_match          : LR value from the match row.
      verbose           : Boolean flag for verbose logging.
      output_filename   : Output file name

    The function constructs the tar file path as:
      <batch>/Seqs/<hfpd_id>/Motifs/ProtPeptide_ELM.txt.tar.gz
    It then opens the tar file, reads the member file ending with "ProtPeptide_ELM.txt",
    computes LR scores for each interaction row, and writes the output file
      ProtPeptide_ELM.lr
    in the same directory as the tar file.

    Returns a log message (string) summarizing the work performed.
    """
    batch, hfpd_id, bnClass, bnCsv, bnDiso, lr_match, verbose, output_filename = args
    tar_path = os.path.join(batch, f"Seqs/{hfpd_id}/Motifs/ProtPeptide_ELM.txt.tar.gz")
    log_messages = []
    
    if not os.path.exists(tar_path):
        msg = f"Warning: .tar file for {hfpd_id} not found in {batch}\n"
        log_messages.append(msg)
        return "".join(log_messages)
    
    if verbose:
        log_messages.append(f"Processing tar file: {tar_path}\n")
    
    lrs = defaultdict(list)
    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            for member in tar.getmembers():
                if member.name.endswith("ProtPeptide_ELM.txt"):
                    fileobj = tar.extractfile(member)
                    if fileobj is None:
                        continue
                    try:
                        df = pd.read_csv(fileobj, header=None, sep='\t', dtype=str)
                    except Exception as e:
                        log_messages.append(f"Error reading {member.name} from {tar_path}: {e}\n")
                        continue
                    for idx, row in df.iterrows():
                        if len(row) < 10:
                            continue
                        pp1 = str(row[0]).strip() + "\t" + str(row[1]).strip()
                        cls = str(row[2]).strip()
                        csv_val = str(row[8]).strip()
                        try:
                            diso_val = float(row[9])
                        except ValueError:
                            diso_val = 0.0
                        diso_bin = 1 if diso_val >= 0.5 else 0
                        lr_class = bnClass.get(cls, 0)
                        lr_csv = bnCsv.get(csv_val, 0)
                        lr_diso = bnDiso.get(str(diso_bin), bnDiso.get(diso_bin, 0))
                        lr_value = lr_match * lr_class * lr_csv * lr_diso
                        lrs[pp1].append((lr_value, cls)) # Store both LR and ELM class for all entries
    except Exception as e:
        log_messages.append(f"Error processing tar file {tar_path}: {e}\n")
        return "".join(log_messages)
    
    out_dir = os.path.dirname(tar_path)
    output_file = os.path.join(out_dir, output_filename)
    try:
        with open(output_file, 'w') as out_f:
            for pp in sorted(lrs.keys()):
                sorted_entries = sorted(lrs[pp], key=lambda x: x[0], reverse=True)
                for lr_val, elm_class in sorted_entries:
                    out_f.write(f"{pp}\t{lr_val}\t{elm_class}\n")
        log_messages.append(f"Wrote output file: {output_file}\n")
    except Exception as e:
        log_messages.append(f"Error writing output file {output_file}: {e}\n")
    
    return "".join(log_messages)

def main():
    parser = argparse.ArgumentParser(
        description="Process a single batch directory for PrePPI scores (ELM version)")
    parser.add_argument('-batch', required=True, help="Path to the batch directory")
    parser.add_argument('-g', required=True, help="Genome basename (e.g., human_AF_AS)")
    parser.add_argument('-b', required=True, help="Path to Bayesian network CSV file")
    parser.add_argument('-o', required=True, help="Output file name")
    parser.add_argument('-v', action='store_true', help="Verbose mode")
    parser.add_argument('-d', action='store_true', help="Debug mode")
    args = parser.parse_args()
    
    verbose = args.v
    debug = args.d
    if debug:
        verbose = True
    
    batch = args.batch
    sys.stdout.write(f"Processing batch directory: {batch}\n")
    
    map_list_file = os.path.join(batch, "fasta", "map_list")
    if not os.path.exists(map_list_file):
        sys.stdout.write(f"Warning: map_list not found in {batch}\n")
        sys.exit(1)
    try:
        map_list = sorted(set(pd.read_csv(os.path.join(batch, 'fasta/map_list'), header=None, sep='\t', dtype='str')[0].to_list()))
    except Exception as e:
        sys.stderr.write(f"Error reading {map_list_file}: {e}\n")
        sys.exit(1)
    
    lr_match, bnClass, bnCsv, bnDiso = readBNs(args.b, verbose=verbose)
    output_filename = args.o if args.o else "ProtPeptide_ELM.lr"
    tasks = [(batch, hfpd_id, bnClass, bnCsv, bnDiso, lr_match, verbose, output_filename) for hfpd_id in map_list]
    
    with concurrent.futures.ProcessPoolExecutor(max_workers=16) as executor:
        results = executor.map(process_tar_file, tasks)
        for res in results:
            sys.stdout.write(res)
    
    sys.stdout.write("Processing completed for batch: " + batch + "\n")

if __name__ == "__main__":
    main()

### Aakash
