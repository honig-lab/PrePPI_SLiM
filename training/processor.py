import argparse
import collections
import conditional
import os
import pandas as pd
import reader
import writer

from __init__ import logging
logger = logging.getLogger(__name__)


def main(args):
    config = reader.read_json(args.config)
    uniprot_ids = reader.read_ids(config["target_uniprot_ids"], "uniprot")
    elm_classes = reader.read_ids(config["target_elm_classes"], "elm_class")

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

    interactions = read_interaction_sets(config["high_confidence_set"], config["exclusion_set"])
    interactions = interactions[["interaction_id", "annotation"]]

    targets = args.targets.split(',')
    hc_sets = collections.defaultdict(set)
    nc_sets = collections.defaultdict(set)
    clue_names = []
    for target in targets:
        found = False
        # Iterate over each batch directory to locate the target file.
        for batch_dir in batch_dirs:
            target_filename = os.path.join(
                batch_dir, "Seqs", target, "Motifs", "ProtPeptide_ELM.txt.tar.gz"
            )
            if os.path.exists(target_filename):
                matches = reader.read_ProtPeptide_ELM(target_filename, map_list)
                found = True
                break  # Use the first found instance or modify if you need to merge data from multiple batches.
        if not found:
            logger.error(f"Target file not found for target: {target}")
            continue

        # If matches is empty or does not contain the expected columns, skip processing this target.
        if matches.empty or not {"uniprot_id1", "uniprot_id2"}.issubset(matches.columns):
            logger.warning(f"Target file {target_filename} produced empty or incomplete data. Skipping target {target}.")
            continue

        # ------------------------ #
        # group_cols = ["hfpd_id1", "hfpd_id2", "elm_class", "uniprot_id1", "uniprot_id2"]
        # matches = matches.groupby(group_cols, as_index=False).max()
        # ------------------------ #

        matches["interaction_id"] = reader.normalize_interactions(matches)
        matches = matches.merge(interactions, how="left").fillna("nc")

        for clue_name, selector in conditional.selector.items():
            if selector:
                subset = matches[selector(matches)]
            else:
                subset = matches
            hc_sets[clue_name] |= set(subset[subset.annotation == "hc"].interaction_id)
            nc_sets[clue_name] |= set(subset[subset.annotation == "nc"].interaction_id)
            clue_names.append(clue_name)

        for clue_name in elm_classes:
            subset = matches[matches.elm_class == clue_name]
            hc_sets[clue_name] |= set(subset[subset.annotation == "hc"].interaction_id)
            nc_sets[clue_name] |= set(subset[subset.annotation == "nc"].interaction_id)
            clue_names.append(clue_name)

    for clue_name in clue_names:
        writer.write_interactions(f"{args.output}/{clue_name}.hc", hc_sets[clue_name])
        writer.write_interactions(f"{args.output}/{clue_name}.nc", nc_sets[clue_name])        


def read_interaction_sets(
        high_confidence_set_filename: str,
        exclusion_set_filename: str
    ) -> pd.DataFrame:
    return pd.concat([
        reader.read_interactions(high_confidence_set_filename, "hc"),
        reader.read_interactions(exclusion_set_filename, "ex"),
    ])


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    parser.add_argument("targets")
    parser.add_argument("output")
    return parser.parse_args()


if __name__ == "__main__":
    main(get_args())
