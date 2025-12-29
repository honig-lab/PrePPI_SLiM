import os
import random
import string
import subprocess

from __init__ import logging
logger = logging.getLogger(__name__)


def random_id(length=8):
    return ''.join(random.sample(string.ascii_letters + string.digits, length))

TEMPLATE_SERIAL = """
#####################################
#$ -S /bin/bash
#$ -wd {wd}
#$ -N {name}
#$ -e qsub/{base}.e$JOB_ID
#$ -o qsub/{base}.o$JOB_ID
#####################################
echo "------------------------------------------------------------------------"
echo "Job started on" `date`
echo "------------------------------------------------------------------------"
source /ifs/home/c2b2/bh_lab/clt47/python/home-3.9.7/bin/activate
python /ifs/home/c2b2/bh_lab/clt47/preppi/prp/training/processor.py {config} {ids} {out}
echo "------------------------------------------------------------------------"
echo "Job ended on" `date`
echo "------------------------------------------------------------------------"
"""

def submit_python_task(config, name, ids, out, wd):
    task_id = "task_{0}".format(random_id())
    task_fn = os.path.join(wd, "qsub", task_id) + '.sh'
    
    open(task_fn, 'w').write(
        TEMPLATE_SERIAL.format(config=config, name=name, ids=ids, out=out, wd=wd, base=task_id)
    )
    subprocess.call('qsub < ' + task_fn, shell=True)
