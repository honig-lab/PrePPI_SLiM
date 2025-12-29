import argparse
import os
import pandas as pd
import reader

from __init__ import logging
logger = logging.getLogger(__name__)


def main(args):
    config = reader.read_json(args.config)

    uniprot_ids = reader.read_ids(config["target_uniprot_ids"], "uniprot")
    num_all_interactions = compute_num_all_interactions(uniprot_ids)
    print(f"num all interactions = {num_all_interactions}")

    hc_interactions = reader.read_interactions(config["high_confidence_set"], "hc")
    num_hc_interactions = len(hc_interactions)
    print(f"num high-confidence interactions = {num_hc_interactions}")

    ex_interactions = reader.read_interactions(config["exclusion_set"], "ex")
    num_ex_interactions = len(ex_interactions)
    print(f"num excluded interactions = {num_ex_interactions}")

    num_true_pos = num_hc_interactions
    num_true_neg = num_all_interactions - num_hc_interactions - num_ex_interactions
    print(f"num TP = {num_true_pos}; num TN = {num_true_neg}")

    scratch_dir = config["scratch_dir"]
    manifest_filename = os.path.join(scratch_dir, "manifest.tsv")
    manifest = pd.read_csv(manifest_filename, sep="\t", header=None)
    manifest.columns = ["config", "ids", "out"]

    match_true_pos, match_true_neg = collect_counts(scratch_dir, "match", manifest)
    pr_match_true_pos = match_true_pos / num_true_pos
    pr_match_true_neg = match_true_neg / num_true_neg
    lr_match = pr_match_true_pos / pr_match_true_neg

    output = []
    output.append(
        ["match", match_true_pos, match_true_neg, pr_match_true_pos, pr_match_true_neg, lr_match, None]
    )

    for clue_name in ["diso_0", "diso_1", "consv_0", "consv_1"]:
        clue_true_pos, clue_true_neg = collect_counts(scratch_dir, clue_name, manifest)
        pr_clue_true_pos = clue_true_pos / num_true_pos
        pr_clue_true_neg = clue_true_neg / num_true_neg
        if pr_clue_true_neg == 0:
            lr_clue = float('inf')
        else:
            lr_clue = pr_clue_true_pos / pr_clue_true_neg
        output.append(
            [clue_name, clue_true_pos, clue_true_neg, pr_clue_true_pos, pr_clue_true_neg, lr_clue, lr_clue / lr_match]
        )

    elm_classes = reader.read_ids(config["target_elm_classes"], "elm_class")
    for clue_name in elm_classes:
        clue_true_pos, clue_true_neg = collect_counts(scratch_dir, clue_name, manifest)
        pr_clue_true_pos = clue_true_pos / num_true_pos
        pr_clue_true_neg = clue_true_neg / num_true_neg
        if pr_clue_true_neg == 0:
            lr_clue = float('inf')
        else:
            lr_clue = pr_clue_true_pos / pr_clue_true_neg
        output.append(
            [clue_name, clue_true_pos, clue_true_neg, pr_clue_true_pos, pr_clue_true_neg, lr_clue, lr_clue / lr_match]
        )

    columns = ["clue", "count(.|tp)", "count(.|tn)", "pr(.|tp)", "pr(.|tn)", "lr(.)", "lr(.)/lr(m)"]
    df = pd.DataFrame(output, columns=columns)
    df.to_csv(os.path.join(scratch_dir, "motif_elm.lr"))
    print(df)


def collect_counts(scratch_dir: str, clue_name: str, manifest: pd.DataFrame) -> tuple[int, int]:
    hc_set = set()
    nc_set = set()
    for i, row in enumerate(manifest.itertuples()):
        hc_fn = os.path.join(scratch_dir, row.out, clue_name) + ".hc"
        nc_fn = os.path.join(scratch_dir, row.out, clue_name) + ".nc"

        hc_set |= set(open(hc_fn).read().splitlines())
        nc_set |= set(open(nc_fn).read().splitlines())
        if i % 100 == 99:
            logger.info(f"[{clue_name} iter={i}] hc={len(hc_set)} nc={len(nc_set)}")
    return len(hc_set), len(nc_set)


def compute_num_all_interactions(uniprot_ids: list[str]) -> int:
    num_uniprot_ids = len(uniprot_ids)
    num_all_interactions = num_uniprot_ids * (num_uniprot_ids - 1) // 2 + num_uniprot_ids
    return num_all_interactions


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("config")
    return parser.parse_args()


if __name__ == "__main__":
    main(get_args())
