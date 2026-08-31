"""Shared locations and executables for the PrePPI-SLiM runtime.

The names intentionally mirror hfpd_python/MODS/Globals.py so the SM and SLiM
controllers have the same maintenance surface.  Only SLiM resources belong
here; importing this module does not validate unrelated PrePPI-SM databases.
"""
from __future__ import annotations

import os
from pathlib import Path

IFS_HOME = Path(os.environ.get("HFPD_IFS_HOME", "/groups/bh6_gp/home"))
IFS_DATA = Path(os.environ.get("HFPD_IFS_DATA", "/groups/bh6_gp/data"))
MAIN_DIRECTORY = Path(os.environ.get("HFPD_DIR", IFS_HOME / "shares/hfpd"))
DATABASE_DIR = IFS_DATA / "shares/databases"
GENOME_DIRECTORY = Path(os.environ.get("HFPD_DATA_DIR", DATABASE_DIR / "hfpd/genomes"))
HFPD_BIN = IFS_DATA / "shares/bin"
HFPD_SCR = MAIN_DIRECTORY / "SCR"

BLASTCMD = IFS_HOME / "shares/blast/current/x64-linux/bin"
GOPHER_BIN = IFS_HOME / "shares/slimsuite_2024/legacy/gopher_V2.py"
GOPHER_DB = DATABASE_DIR / "uniprot/uniref100"
MUSCLE = IFS_HOME / "shares/muscle/muscle"
JACKHAMMER_DIR = IFS_HOME / "shares/hmmer-3.1b2-linux-intel-x86_64/binaries"
IUPRED = IFS_HOME / "shares/iupred/iupred"
ELM_CLASSES = IFS_DATA / "shares/hfpd/data/Peptides/elm_2025/elm_classes_2025.tsv"
HMMS = IFS_DATA / "shares/hfpd/data/Peptides/hmms_2025"
PFAM_PERL = IFS_HOME / "shares/perl-5.40.0/install/bin/perl"
CONDA_ENV = Path(os.environ.get("HFPD_CONDA_ENV", "/groups/bh6_gp/software/conda_envs/v2"))
PYTHON = CONDA_ENV / "bin/python3"
EMAIL_DIR = IFS_HOME / "shares/hfpd/Email"
MAX_ARRAY_VAL = int(os.environ.get("HFPD_MAX_ARRAY_VAL", "1000"))


def validate_runtime(*, genome_directory: bool = True) -> None:
    """Fail early with paths relevant to this runtime invocation."""
    required = {"PrePPI-SLiM directory": MAIN_DIRECTORY, "SCR directory": HFPD_SCR}
    if genome_directory:
        required["genome directory"] = GENOME_DIRECTORY
    missing = [f"{label}: {path}" for label, path in required.items() if not path.is_dir()]
    if not PYTHON.is_file():
        missing.append(f"conda Python: {PYTHON}")
    if missing:
        raise RuntimeError("Required PrePPI-SLiM runtime path(s) are unavailable:\n  " + "\n  ".join(missing))
