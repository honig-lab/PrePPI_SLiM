import argparse
import numpy as np
import os
import pandas as pd
import reader
import shutil

from __init__ import logging
logger = logging.getLogger(__name__)

if shutil.which("qsub"):
    import qsub as scheduler
else:
    import sbatch as scheduler


def main(args, chunks=500):
    config = reader.read_json(args.config)
    uniprot_ids = reader.read_ids(config["target_uniprot_ids"])

    # map_list_filename = os.path.join(config["hfpd_project_home"], "fasta/map_list")
    # map_list = reader.read_map_list(map_list_filename, uniprot_ids)

    # Get all relevant batch directories.
    batch_dirs = reader.get_batch_directories(config["hfpd_project_home"])
    
    # Read and combine the map_list files from all batches.
    map_list_dfs = []
    for batch_dir in batch_dirs:
        map_list_filename = os.path.join(batch_dir, "fasta", "map_list")
        df = reader.read_map_list(map_list_filename, uniprot_ids)
        map_list_dfs.append(df)
    map_list = pd.concat(map_list_dfs)

    map_list_chunks = np.array_split(map_list, chunks)

    working_dir = os.path.join(config["scratch_dir"])
    output_dir = os.path.join(working_dir, "out")
    script_dir = os.path.join(working_dir, "bat")

    if not os.path.exists(working_dir):
        os.makedirs(working_dir)

    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    if not os.path.exists(script_dir):
        os.makedirs(script_dir)

    job_specs = []
    for i, chunk in enumerate(map_list_chunks):
        spec_hfpd_ids = ",".join(chunk.hfpd_id)
        spec_filename = f"out/int_{i:03}"
        job_specs.append([args.config, spec_hfpd_ids, spec_filename])
    
    for config_fn, ids, out in job_specs:
        scheduler.submit_python_task(config_fn, f"prp_main", ids, out, working_dir)
    
    df = pd.DataFrame(job_specs)
    df.to_csv(os.path.join(working_dir, "manifest.tsv"), sep="\t", header=None, index=None)


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    return parser.parse_args()


if __name__ == "__main__":
    main(get_args())
