import os
import random
import string
import subprocess

from __init__ import logging
logger = logging.getLogger(__name__)


def random_id(length=8):
    return ''.join(random.sample(string.ascii_letters + string.digits, length))

TEMPLATE_SERIAL = """#!/bin/bash
#SBATCH --chdir={wd}
#SBATCH --job-name={name}
#SBATCH --error=bat/{base}.e%j
#SBATCH --output=bat/{base}.o%j

echo "------------------------------------------------------------------------"
echo "Job started on" `date`
echo "------------------------------------------------------------------------"
PRP_DIR=/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide
source $PRP_DIR/training/conda.sh
conda activate $PRP_DIR/conda/env
python $PRP_DIR/training/processor.py {config} {ids} {out}
echo "------------------------------------------------------------------------"
echo "Job ended on" `date`
echo "------------------------------------------------------------------------"
"""

def submit_python_task(config, name, ids, out, wd):
    task_id = "task_{0}".format(random_id())
    task_fn = os.path.join(wd, "bat", task_id) + '.sh'
    
    open(task_fn, 'w').write(
        TEMPLATE_SERIAL.format(config=config, name=name, ids=ids, out=out, wd=wd, base=task_id)
    )
    subprocess.call('sbatch < ' + task_fn, shell=True)
