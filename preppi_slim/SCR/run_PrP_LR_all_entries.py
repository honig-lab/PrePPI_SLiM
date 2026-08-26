#!/usr/bin/env python3

"""
run_PrP_LR_all_entries.py

This script scans a fixed genome directory for batch directories matching a given
genome basename, writes an sbatch script for each batch into the batch's
Pipeline/PrP_LR folder, and submits one job per batch.

Current LR Path:
    /groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/human_AF_bn_training

Usage:
    python run_PrP_LR_entries.py -g <genome_basename> -batch <True/False> -b <BN_file> -o <output_filename> [-v]

Arguments:
  -g     Genome basename (e.g., human_AF_AS)
  -batch True/False
  -o     Output file name
  -b     Path to Bayesian network CSV file
  -v     Verbose mode
"""

import os
import sys
import glob
import argparse
import subprocess
import shlex

def main():
    parser = argparse.ArgumentParser(
        description="Submit SLURM jobs for each batch directory")
    parser.add_argument('-g', required=True, help="Genome basename (e.g., human_AF_AS)")
    parser.add_argument('-batch', required=True, help="Genome in Batches (True/False)")
    parser.add_argument('-b', required=True, help="Path to Bayesian network CSV file")
    parser.add_argument('-i', '--input-filename', required=True,
                        help="Per-protein candidate CSV.gz filename")
    parser.add_argument('-o', required=True, help="Output file name")
    parser.add_argument('-v', action='store_true', help="Verbose mode")
    args = parser.parse_args()
    
    verbose = args.v
    genome = args.g
    batch_mode = args.batch.lower() in ["true", "1", "yes"]
    bn_file = args.b
    output_filename = args.o
    input_filename = args.input_filename
    genome_dir = os.environ.get(
        "HFPD_DATA_DIR", "/groups/bh6_gp/data/shares/databases/hfpd/genomes")
    preppi_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    module_file = os.path.join(preppi_dir, "MODS", "PrP_LR_all_entries.py")
    
    # Find batch directories matching the genome basename pattern.
    if batch_mode == True:
        batch_dirs = sorted(glob.glob(os.path.join(genome_dir, f"{genome}_batch*")))
    else:
        batch_dirs = [os.path.join(genome_dir, genome)]
    if verbose:
        print(f"Found {len(batch_dirs)} batch directories matching {genome}")
    
    for batch in batch_dirs:
        # Create the Pipeline/PrP_LR directory if it doesn't exist.
        pipeline_dir = os.path.join(batch, "Pipeline", "PrP_LR")
        os.makedirs(pipeline_dir, exist_ok=True)
        
        # Define the sbatch script file path.
        sbatch_script = os.path.join(pipeline_dir, "submit_PrP_LR.sbatch")
        batch_basename = os.path.basename(batch)
        
        # Build the sbatch script content.
        # Update the path to PrP_LR.py as appropriate.
        sbatch_content = f"""#!/bin/bash
#SBATCH --job-name=PrP_LR_{batch_basename}
#SBATCH -o {pipeline_dir}/PrP_LR.o%j
#SBATCH -e {pipeline_dir}/PrP_LR.e%j
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=18
#SBATCH --mem-per-cpu=4G
#SBATCH --time=09:00:00
#SBATCH --partition=cpu

# Load environment
source ~/.bashrc
conda activate /groups/bh6_gp/software/conda_envs/v2

# Run the processing module for this batch.
python {shlex.quote(module_file)} -batch {shlex.quote(batch)} \
  -g {shlex.quote(genome)} -i {shlex.quote(input_filename)} \
  -b {shlex.quote(bn_file)} -o {shlex.quote(output_filename)} {"-v" if verbose else ""}
"""
        # Write the sbatch script.
        with open(sbatch_script, 'w') as f:
            f.write(sbatch_content)
        if verbose:
            print(f"Created sbatch script for batch {batch_basename} at {sbatch_script}")
        
        # Submit the job.
        try:
            result = subprocess.run(["sbatch", sbatch_script],
                                    capture_output=True, text=True)
            if result.returncode == 0:
                print(f"Submitted job for batch {batch_basename}: {result.stdout.strip()}")
            else:
                print(f"Error submitting job for batch {batch_basename}: {result.stderr.strip()}")
        except Exception as e:
            print(f"Exception while submitting job for batch {batch_basename}: {e}")

if __name__ == "__main__":
    main()

### Aakash
