import json
import numpy as np
import pandas as pd
import glob
import os

from __init__ import logging
logger = logging.getLogger(__name__)


def get_batch_directories(base_dir: str) -> list[str]:
    """
    Given a base directory (e.g., .../human_v2), return a list of directories
    that match the batch pattern (e.g., human_v2_batch1, human_v2_batch2, etc.).
    If no batch directories are found, return [base_dir].
    """
    # Look for directories that have the base name with a _batch suffix.
    pattern = base_dir + "_batch*"
    batch_dirs = glob.glob(pattern)
    if not batch_dirs:
        return [base_dir]
    return batch_dirs


def read_json(filename: str) -> dict:
    with open(filename, "r") as f:
        obj = json.load(f)
        logger.info(f"read json file {filename}")
        logger.info(json.dumps(obj, indent=2))
        return obj


def read_ids(filename: str, id_type: str = "uniprot") -> list[str]:
    with open(filename, "r") as f:
        ids = f.read().splitlines()
        logger.info(f"read {len(ids)} {id_type} ids")
        return ids


def read_map_list(filename: str, uniprot_ids: list[str] = None) -> pd.DataFrame:
    columns = ["hfpd_id", "uniprot_id"]
    converters = {
        0: str,
        1: lambda s: s.strip(">"),
    }
    df = pd.read_csv(filename, header=None, sep="\t", converters=converters)
    df.columns = columns
    logger.info(f"read {len(df)} rows from 'map_list' file: {filename}")

    if uniprot_ids:
        df = df[df.uniprot_id.isin(set(uniprot_ids))].copy()
        logger.info(f"selected {len(df)} rows using set of {len(uniprot_ids)} uniprot ids")

    return df


def read_ProtPeptide_ELM(filename: str, map_list: pd.DataFrame = None) -> pd.DataFrame:
    columns = [
        "hfpd_id1",         # 0
        "hfpd_id2",         # 1
        "elm_class",        # 2
        # "domain_idx1",      # 3
        # "domain_idx2",      # 4
        # "motif",            # 5
        # "motif_idx1",       # 6
        # "motif_idx2",       # 7
        "conservation_bin", # 8 -> 3
        "disorder_score",   # 9 -> 4
    ]
    converters = {
        0: str,
        1: str,
    }

    df_chunks = []
    chunksize = 1_000_000
    try:
        text_reader = pd.read_csv(filename, header=None, sep="\t", converters=converters,
                                  usecols=[0, 1, 2, 8, 9], iterator=True, chunksize=chunksize)
    except pd.errors.EmptyDataError:
        logger.warning(f"EmptyDataError encountered when reading {filename}. Returning empty DataFrame.")
        return pd.DataFrame(columns=columns)
    except Exception as e:
        logger.error(f"Error reading {filename}: {e}")
        return pd.DataFrame(columns=columns)

    for df in text_reader:
        if df.empty:
            logger.warning(f"No data in chunk from file {filename}.")
            continue
        df.columns = columns
        logger.info(f"read {len(df)} rows from 'ProtPeptide_ELM' file: {filename}")

        if map_list is not None:
            for idx in ["1", "2"]:
                df = df.merge(map_list.rename(columns=lambda name: name + idx), how="inner")
            logger.info(f"selected {len(df)} rows using map_list of {len(map_list)} rows")
        df_chunks.append(df)

    if not df_chunks:
        logger.warning(f"No valid data found in file {filename}. Returning empty DataFrame.")
        return pd.DataFrame(columns=columns)
    
    return pd.concat(df_chunks)


def read_interactions(filename: str, annotation: str) -> set:
    df = pd.read_csv(filename, header=None)
    df.columns = ["uniprot_id1", "uniprot_id2"]
    df["interaction_id"] = normalize_interactions(df)
    df["annotation"] = annotation
    return df


def normalize_interactions(df: pd.DataFrame) -> list[str]:
    interaction_columns = ["uniprot_id1", "uniprot_id2"]
    return [
        tuple(row) for row in
        np.sort(df[interaction_columns].values, axis=1)
    ]
