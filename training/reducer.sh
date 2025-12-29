#!/bin/bash
#SBATCH --chdir=/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/human_AF_bn_training/test_008
#SBATCH --job-name=prp_reduce
#SBATCH --error=bn_out.e%j
#SBATCH --output=bn_out.o%j

PRP_DIR=/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide
# source $PRP_DIR/training/conda.sh
# conda activate $PRP_DIR/conda/env
python $PRP_DIR/training/reducer.py $PRP_DIR/training/config.json
