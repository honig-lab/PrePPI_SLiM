#!/bin/bash

### config.json
cat > config.json << EOF
{
    "scratch_dir": "/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/human_AF_bn_training/test_008",
    "hfpd_project_home": "/groups/bh6_gp/data/shares/databases/hfpd/genomes/human_AF_AS",
    "target_elm_classes": "/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/datasets/target_elm_classes_human_AF.csv",
    "target_uniprot_ids": "/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/datasets/target_uniprot_ids_human_AF.csv",
    "high_confidence_set": "/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/datasets/HINT_2024_woIsoforms_UniProt_Pairs.csv",
    "exclusion_set": "/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/datasets/exclusion_set_2023.csv"
}
EOF

### Comments
: <<'EOF'
### Description

Genome = Human AF (run in batches)
hfpd_project_home above mentions the genome basename. Change PRP_DIR everywhere if required.

TP = HINT 2024 Bi w/o Isoforms
TN = Total - (TP + PrePPI 2023)
Target ELM classes = Human AF (296; 2025 ELM classes)
UniProt IDs: Human AF

### Training Direction:
1. ./user_input.sh
2. ./driver.sh
3. sbatch reducer.sh
EOF

### Copying user_input.sh to $SCRATCH_DIR

# Path to config.json
PRP_DIR="/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide"

# Extract scratch_dir value from config.json
SCRATCH_DIR=$(grep '"scratch_dir"' ${PRP_DIR}/training/config.json | awk -F ': "' '{print $2}' | tr -d '",')

if [ -d "$SCRATCH_DIR" ]; then
    echo "Error: Directory $SCRATCH_DIR already exists!" >&2
    exit 1
else
    mkdir "$SCRATCH_DIR"
fi

# Write config.json content as README in SCRATCH_DIR
cp --no-preserve=mode "$PRP_DIR/training/user_input.sh" "$SCRATCH_DIR/README"

### Aakash
