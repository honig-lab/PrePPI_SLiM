#!/bin/bash

PRP_DIR=/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide
# source $PRP_DIR/training/conda.sh
# conda activate $PRP_DIR/conda/env
python $PRP_DIR/training/driver.py $PRP_DIR/training/config.json

### Writing reducer.sh

# Path to config.json
CONFIG_JSON="$PRP_DIR/training/config.json"

# Extract scratch_dir value from config.json
SCRATCH_DIR=$(grep '"scratch_dir"' $CONFIG_JSON | awk -F ': "' '{print $2}' | tr -d '",')

# Generate reducer.sh
cat <<EOF > reducer.sh
#!/bin/bash
#SBATCH --chdir=$SCRATCH_DIR
#SBATCH --job-name=prp_reduce
#SBATCH --error=bn_out.e%j
#SBATCH --output=bn_out.o%j

PRP_DIR=$PRP_DIR
# source \$PRP_DIR/training/conda.sh
# conda activate \$PRP_DIR/conda/env
python \$PRP_DIR/training/reducer.py \$PRP_DIR/training/config.json
EOF

# Make the script executable
chmod 755 reducer.sh

### Aakash
