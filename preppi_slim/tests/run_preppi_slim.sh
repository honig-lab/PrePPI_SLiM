#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  preppi_pipeline.sh [options]

Options:
  -g, --genome NAME          Genome/run name (prompted if omitted)
  -f, --fasta FILE           Input FASTA (default: input.fa beside this script)
  -s, --steps "2 4a"         Steps to run (prompted if omitted)
  -n, --max-sequences N      Use only the first N FASTA records (small test run)
  -b, --bn-file FILE         Bayesian-network CSV required by step 4b
  -o, --lr-output NAME       LR output filename (default: PrP_LR.txt)
      --batch                Treat the genome name as a batch basename in step 4b
      --dry-run              Print commands without running or submitting them
  -h, --help                 Show this help

Steps:
  2   Set up the genome and run IUPRED
  4a  Run the PrePPI-SLiM protein-peptide pipeline
  4b  Calculate protein-peptide likelihood ratios

Example small run:
  ./preppi_pipeline.sh -g my_test -f proteins.fa -n 10 -s "2 4a"
EOF
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
slim_dir=$(cd -- "$script_dir/.." && pwd)
genome_dir="${HFPD_DATA_DIR:-/groups/bh6_gp/data/shares/databases/hfpd/genomes}"
jackal_dir="${JACKALDIR:-/groups/bh6_gp/home/shares/jackal/bin/ubuntu-12.04/jackal.dir}"
fasta_file="$script_dir/input.fa"
genome=""
user_steps=""
max_sequences=0
bn_file=""
lr_output="PrP_LR.txt"
batch_mode="False"
dry_run=0

while (( $# > 0 )); do
  case "$1" in
    -g|--genome) genome=${2:?"Missing value for $1"}; shift 2 ;;
    -f|--fasta) fasta_file=${2:?"Missing value for $1"}; shift 2 ;;
    -s|--steps) user_steps=${2:?"Missing value for $1"}; shift 2 ;;
    -n|--max-sequences) max_sequences=${2:?"Missing value for $1"}; shift 2 ;;
    -b|--bn-file) bn_file=${2:?"Missing value for $1"}; shift 2 ;;
    -o|--lr-output) lr_output=${2:?"Missing value for $1"}; shift 2 ;;
    --batch) batch_mode="True"; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$max_sequences" =~ ^[0-9]+$ ]] || {
  echo "--max-sequences must be a non-negative integer." >&2
  exit 2
}

if [[ -z "$genome" ]]; then
  read -r -p "Genome/run name: " genome
fi
[[ -n "$genome" ]] || { echo "Genome/run name cannot be empty." >&2; exit 2; }

if [[ -z "$user_steps" ]]; then
  printf '\nSelect steps: 2 (setup), 4a (SLiM), 4b (LR)\n'
  read -r -p "Enter step numbers: " user_steps
fi
read -r -a steps <<< "$user_steps"
(( ${#steps[@]} > 0 )) || { echo "At least one step is required." >&2; exit 2; }

export HFPD_DIR="$slim_dir"
export HFPD_DATA_DIR="$genome_dir"
export PERL5LIB="$slim_dir${PERL5LIB:+:$PERL5LIB}"
export JACKALDIR="$jackal_dir"
export PERL_PERTURB_KEYS=0
export PERL_HASH_SEED=0

run() {
  printf '+ '
  printf '%q ' "$@"
  printf '\n'
  (( dry_run == 1 )) || "$@"
}

prepared_fasta="$fasta_file"
cleanup_file=""
cleanup() {
  [[ -z "$cleanup_file" ]] || rm -f -- "$cleanup_file"
}
trap cleanup EXIT

needs_fasta=0
includes_slim=0
for step in "${steps[@]}"; do
  [[ "$step" == "2" ]] && needs_fasta=1
  [[ "$step" == "4a" ]] && includes_slim=1
done

if (( needs_fasta == 1 )); then
  [[ -r "$fasta_file" ]] || { echo "FASTA file is not readable: $fasta_file" >&2; exit 1; }
  if (( max_sequences > 0 )); then
    cleanup_file=$(mktemp "${TMPDIR:-/tmp}/preppi_slim_fasta.XXXXXX")
    awk -v limit="$max_sequences" '
      /^>/ { count++ }
      count <= limit { print }
    ' "$fasta_file" > "$cleanup_file"
    grep -q '^>' "$cleanup_file" || { echo "No FASTA records found in $fasta_file" >&2; exit 1; }
    prepared_fasta="$cleanup_file"
    echo "Small-run input: first $max_sequences FASTA record(s) from $fasta_file"
  fi
fi

echo "Genome/run name: $genome"
echo "PrePPI-SLiM code: $slim_dir"

for step in "${steps[@]}"; do
  case "$step" in
    2)
      if (( includes_slim == 1 )); then
        echo "[Step 2] Setting up genome (IUPRED will run as part of step 4a)"
        run "$slim_dir/SCR/setup_genome.pl" "$genome" -f "$prepared_fasta" -q
      else
        echo "[Step 2] Setting up genome and running IUPRED"
        run "$slim_dir/SCR/setup_genome.pl" "$genome" -f "$prepared_fasta"
      fi
      ;;
    4a)
      (( dry_run == 1 )) || [[ -d "$genome_dir/$genome" ]] || {
        echo "Genome directory does not exist: $genome_dir/$genome (run step 2 first)." >&2
        exit 1
      }
      echo "[Step 4a] Running PrePPI-SLiM protein-peptide pipeline"
      run "$slim_dir/SCR/run_elm.pl" "$genome"
      ;;
    4b)
      if [[ -z "$bn_file" ]]; then
        read -r -p "Path to Bayesian-network CSV: " bn_file
      fi
      [[ -f "$bn_file" ]] || { echo "BN file does not exist: $bn_file" >&2; exit 1; }
      echo "[Step 4b] Calculating protein-peptide likelihood ratios"
      run python3 "$slim_dir/SCR/run_PrP_LR.py" \
        -g "$genome" -batch "$batch_mode" -b "$bn_file" -o "$lr_output"
      ;;
    *)
      echo "Invalid step: $step" >&2
      exit 2
      ;;
  esac
done

echo "Pipeline commands completed. Submitted SLURM jobs may still be running."
