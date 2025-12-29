selector = {
    "match": None,
    "consv_0": lambda df: df.conservation_bin == 0,
    "consv_1": lambda df: df.conservation_bin == 1,
    "diso_0": lambda df: df.disorder_score < 0.5,
    "diso_1": lambda df: df.disorder_score >= 0.5,

    # todo: add class selectors 
}
