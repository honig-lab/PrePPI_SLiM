import os
import pandas as pd

from __init__ import logging
logger = logging.getLogger(__name__)


def create_directory_if_missing(filename: str):
    directory = os.path.dirname(filename)
    if not os.path.exists(directory):
        os.makedirs(directory)
        logger.info(f"created dir {directory}")


def write_interactions(filename: str, interactions: set[tuple[str, str]]):
    columns = ["uniprot_id1", "uniprot_id2"]
    df = pd.DataFrame(sorted(interactions), columns=columns)
    create_directory_if_missing(filename)
    df.to_csv(filename, header=None, index=None)
    logger.info(f"wrote {len(df)} interactions to {filename}")