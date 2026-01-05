#!/bin/bash

# User Inputs
fasta_file="input_woCDD.fa"  # Change if needed
test_dir=$(dirname "$(realpath "$0")")
hfpd_dir="/groups/bh6_gp/as7656/research/github/for_hpc/PrePPI/minimal-hfpd"
genome_dir="/groups/bh6_gp/data/shares/databases/hfpd/genomes"
jackal_dir="/groups/bh6_gp/home/shares/jackal/bin/ubuntu-12.04/jackal.dir"

# ENV Variables
export HFPD_DIR=${hfpd_dir}
export PERL5LIB=${hfpd_dir}
export JACKALDIR=${jackal_dir}
export PERL_PERTURB_KEYS=0  # Sets same random hashing
export PERL_HASH_SEED=0  # Sets same random hashing

# load library functions
source $hfpd_dir/tests/pipeline_test_functions.sh

# ---------------- USER INPUTS ----------------
read -p "Genome: " genome
while [[ -z "$genome" ]]; do
  echo "Genome base cannot be empty!"
  read -p "Genome: " genome
done

parsed_fasta_file="input.fa"
echo -e "\nGenome Name: ${genome}"

# ---------------- USER STEP SELECTION ----------------
echo -e "\nSelect steps to execute:"
echo "1 - Parse Sequences as per CDD Domain Search"
echo "2 - Setup genome (+ IUPRED step)"
echo "3a - Copy AFDB structures"
echo "3b - Homology Modeling (NEST)"
echo "4a - Protein-Peptide (PRD & Motifs)"
echo "4b - Calculate LR for PrP Interactions"
echo "6 - Miscellaneous (if uncommented)"
read -p "Enter step numbers: " user_steps

# Convert input into an array
IFS=' ' read -r -a steps <<< "$user_steps"

# ---------------- EXECUTE SELECTED STEPS ----------------
for step in "${steps[@]}"; do
  case "$step" in
    1)
      echo -e "\n[Step 1] Parsing sequences based on CDD domain search..."
      ${hfpd_dir}/SCR/setup_parse_sequences.pl ${fasta_file} ${parsed_fasta_file}
      ;;
      
    2)
      echo -e "\n[Step 2] Setting up genome directory and running IUPRED..."
      ${hfpd_dir}/SCR/setup_genome.pl ${genome} -f ${parsed_fasta_file}
      ;;
      
    3a)
      echo -e "\n[Step 3a] Copying AFDB structures..."
      bash ${hfpd_dir}/tests/full_PrePPI/miscellaneous/cp_precomp_data.sh ${genome}
      ;;
      
    3b)
      echo -e "\n[Step 3b] Running Homology Modeling (NEST)..."
      ${hfpd_dir}/SCR/NEST.pl ${genome}
      ;;

    4a)
      echo -e "\n[Step 4] Running Protein-Peptide (ELM)..."
      ${hfpd_dir}/SCR/run_elm.pl ${genome}
      ;;

    4b)
      echo -e "\n[Step 4] Calculating LR for PrP Interactions..."
      # Read the path of the Bayesian Network file
      read -p "Path of the Bayesian Network File: " bn_file
      while [[ ! -f "$bn_file" ]]; do
        echo "Invalid input! File does not exist. Please enter a valid file path."
        read -p "Path of the Bayesian Network File: " bn_file
      done
      python ${hfpd_dir}/SCR/run_PrP_LR.py -g ${genome} -batch "False" -b ${bn_file}
      ;;

    6)
     echo -e "\n[Step 9] Miscellaneous if uncommented..."
     ## Reset Protein-Peptide Pipeline
     reset_prp=1
     if [ $reset_prp == 1 ]; then
         echo -e "Resetting the Protein-Peptide Pipeline.\n"
         rm -rf ${genome_dir}/${genome}/Pipeline/run_elm.pip
         find ${genome_dir}/${genome}/Pipeline/ -type d | grep -E "FindMotifs_ELM|FindPRDs_ELM|Gopher|MotifConsv|MuscleG|ProtPeptide_ELM" | xargs -I {} rm -rf {}
     fi
     ;;
      
    *)
      echo "Invalid step: $step. Skipping."
      ;;
  esac
done

echo -e "\nPipeline execution completed!"

# Restart Pipeline
## Step1: Delete all pending or unfinished jobs.
# pipeline_step="Skan"
## Step2: Run it with -q to check the directories.
# ${hfpd_dir}/SCR/restart_pipeline.pl $pipeline_step ${genome} -q
## Step3: Run it without -q to finish the incomplete jobs
# ${hfpd_dir}/SCR/restart_pipeline.pl $pipeline_step ${genome}

### Aakash
