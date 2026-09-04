#!/usr/bin/env python3

"""
run_PrP_LR.py

This script scans a fixed genome directory for batch directories matching a given
genome basename, writes an sbatch script for each batch into the batch's
Pipeline/PrP_LR.pip folder, and submits one job per batch.

Current LR Path:
    /groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/human_AF_bn_training

Usage:
    python run_PrP_LR.py -g <genome_basename> -batch <True/False> -b <BN_file> -o <out_file_name> [-v]

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

CONDA_ENV = "/groups/bh6_gp/software/conda_envs/v2"
CONDA_PYTHON = os.path.join(CONDA_ENV, "bin", "python3")

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
    if not os.path.isfile(CONDA_PYTHON) or not os.access(CONDA_PYTHON, os.X_OK):
        raise SystemExit(
            f"Required conda environment is unavailable: {CONDA_ENV} "
            f"(expected {CONDA_PYTHON})")
    genome_dir = os.environ.get(
        "HFPD_DATA_DIR", "/groups/bh6_gp/data/shares/databases/hfpd/genomes")
    preppi_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    module_file = os.path.join(preppi_dir, "MODS", "PrP_LR.py")
    
    # Find batch directories matching the genome basename pattern.
    if batch_mode == True:
        batch_dirs = sorted(glob.glob(os.path.join(genome_dir, f"{genome}_batch*")))
    else:
        batch_dirs = [os.path.join(genome_dir, genome)]
    if verbose:
        print(f"Found {len(batch_dirs)} batch directories matching {genome}")
    
    for batch in batch_dirs:
        # Create the pipeline state directory if it does not exist.
        pipeline_dir = os.path.join(batch, "Pipeline", "PrP_LR.pip")
        os.makedirs(pipeline_dir, exist_ok=True)
        
        # Define the sbatch script file path.
        sbatch_script = os.path.join(pipeline_dir, "submit_PrP_LR.sbatch")
        batch_basename = os.path.basename(batch)
        
        # Build the sbatch script content.
        # Update the path to PrP_LR.py as appropriate.
        log_out = os.path.join(pipeline_dir, "PrP_LR.o%j") if verbose else "/dev/null"
        log_err = os.path.join(pipeline_dir, "PrP_LR.e%j") if verbose else "/dev/null"
        sbatch_content = f"""#!/bin/bash
#SBATCH --job-name=PrP_LR_{batch_basename}
#SBATCH -o {log_out}
#SBATCH -e {log_err}
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=18
#SBATCH --mem-per-cpu=4G
#SBATCH --time=09:00:00
#SBATCH --partition=cpu

# Use the required PrePPI-SLiM conda environment.
export CONDA_PREFIX={shlex.quote(CONDA_ENV)}
export CONDA_DEFAULT_ENV={shlex.quote(CONDA_ENV)}
export PATH={shlex.quote(os.path.join(CONDA_ENV, "bin"))}:$PATH
export HFPD_DIR={shlex.quote(preppi_dir)}
export PYTHONPATH={shlex.quote(preppi_dir)}:${{PYTHONPATH:-}}

# Run the processing module for this batch.
{shlex.quote(CONDA_PYTHON)} {shlex.quote(module_file)} -batch {shlex.quote(batch)} \
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
                raise RuntimeError(
                    f"Error submitting job for batch {batch_basename}: "
                    f"{result.stderr.strip()}"
                )
        except Exception as e:
            raise SystemExit(
                f"Exception while submitting job for batch {batch_basename}: {e}"
            ) from e

if __name__ == "__main__":
    main()

### Aakash
