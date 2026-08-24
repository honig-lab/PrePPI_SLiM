#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_preppi_slim.sh [options]

Options:
  -g, --genome NAME          Genome/run name (prompted if omitted)
  -f, --fasta FILE           Input FASTA (default: input.fasta beside this script)
  -s, --step STEP            One step to run (prompted if omitted)
  -n, --max-sequences N      Use only the first N FASTA records (small test run)
  -b, --bn-file FILE         Bayesian-network CSV required by step 4b
  -o, --lr-output NAME       LR output filename (default: PrP_LR.txt)
      --batch                Treat the genome name as a batch basename in step 4b
      --reset-setup          Back up and replace an incomplete step 2 pipeline
      --reset-slim           Back up and replace the step 4a controller state
      --debug                Retain per-task SLURM output and error logs
      --dry-run              Print commands without running or submitting them
  -h, --help                 Show this help

Steps:
  2   Set up the genome and run IUPRED
  4a  Run the PrePPI-SLiM protein-peptide pipeline
  4b  Calculate protein-peptide likelihood ratios

Example small run:
  ./run_preppi_slim.sh -g my_test -f proteins.fa -n 10 -s 2
EOF
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
slim_dir=$(cd -- "$script_dir/.." && pwd)
genome_dir="${HFPD_DATA_DIR:-/groups/bh6_gp/data/shares/databases/hfpd/genomes}"
fasta_file="$script_dir/input.fasta"
genome=""
user_steps=""
max_sequences=0
bn_file=""
lr_output="PrP_LR.txt"
batch_mode="False"
reset_setup=0
reset_slim=0
debug_mode=0
dry_run=0

while (( $# > 0 )); do
  case "$1" in
    -g|--genome) genome=${2:?"Missing value for $1"}; shift 2 ;;
    -f|--fasta) fasta_file=${2:?"Missing value for $1"}; shift 2 ;;
    -s|--step|--steps) user_steps=${2:?"Missing value for $1"}; shift 2 ;;
    -n|--max-sequences) max_sequences=${2:?"Missing value for $1"}; shift 2 ;;
    -b|--bn-file) bn_file=${2:?"Missing value for $1"}; shift 2 ;;
    -o|--lr-output) lr_output=${2:?"Missing value for $1"}; shift 2 ;;
    --batch) batch_mode="True"; shift ;;
    --reset-setup) reset_setup=1; shift ;;
    --reset-slim) reset_slim=1; shift ;;
    --debug) debug_mode=1; shift ;;
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
  printf '\nSelect one step: 2 (setup), 4a (SLiM), 4b (LR)\n'
  read -r -p "Enter step: " user_steps
fi
read -r -a steps <<< "$user_steps"
(( ${#steps[@]} == 1 )) || {
  echo "Run exactly one step at a time. Wait for step 2 to complete before running step 4a." >&2
  exit 2
}

export HFPD_DIR="$slim_dir"
export HFPD_DATA_DIR="$genome_dir"
export PERL5LIB="$slim_dir${PERL5LIB:+:$PERL5LIB}"
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

step=${steps[0]}
needs_fasta=0
[[ "$step" == "2" ]] && needs_fasta=1

if (( needs_fasta == 1 )); then
  [[ -r "$fasta_file" ]] || { echo "FASTA file is not readable: $fasta_file" >&2; exit 1; }
  if (( max_sequences > 0 )); then
    temp_root=${TMPDIR:-/tmp}
    if [[ ! -d "$temp_root" || ! -w "$temp_root" ]]; then
      echo "Temporary directory is unavailable: $temp_root; using /tmp instead." >&2
      temp_root=/tmp
    fi
    cleanup_file=$(mktemp "$temp_root/preppi_slim_fasta.XXXXXX")
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

case "$step" in
    2)
      setup_dir="$genome_dir/$genome/Pipeline/Setup.pip"
      setup_stage="$setup_dir/Setup.stage"
      if [[ -d "$setup_dir" ]]; then
        if grep -q "Pipeline complete" "$setup_stage" 2>/dev/null; then
          echo "Step 2 is already complete for $genome."
          exit 0
        fi
        if (( reset_setup == 0 )); then
          echo "An incomplete step 2 pipeline already exists: $setup_dir" >&2
          echo "Confirm that no setup jobs are active, then rerun with --reset-setup." >&2
          exit 1
        fi
        setup_backup="${setup_dir}.incomplete.$(date +%Y%m%d_%H%M%S)"
        echo "Backing up incomplete setup pipeline to: $setup_backup"
        run mv "$setup_dir" "$setup_backup"
      fi
      echo "[Step 2] Setting up genome and running IUPRED"
      run "$slim_dir/SCR/setup_genome.pl" "$genome" -f "$prepared_fasta"
      ;;
    4a)
      setup_stage="$genome_dir/$genome/Pipeline/Setup.pip/Setup.stage"
      if (( dry_run == 0 )); then
        id_list="$genome_dir/$genome/fasta/id_list"
        [[ -s "$id_list" ]] || { echo "Target list is missing or empty: $id_list" >&2; exit 1; }
        missing_disorder=0
        target_count=0
        while IFS= read -r target; do
          [[ -n "$target" ]] || continue
          (( target_count += 1 ))
          if [[ ! -s "$genome_dir/$genome/Seqs/$target/disorder.fa" ]]; then
            echo "Missing IUPRED output: Seqs/$target/disorder.fa" >&2
            missing_disorder=1
          fi
        done < "$id_list"
        (( missing_disorder == 0 )) || {
          echo "Step 2 has incomplete IUPRED outputs; step 4a will not be submitted." >&2
          exit 1
        }
        echo "Verified IUPRED output for $target_count target(s)."
        if ! grep -q "Pipeline complete" "$setup_stage" 2>/dev/null; then
          echo "Warning: Setup.stage has no completion marker, but every IUPRED output exists; proceeding with step 4a." >&2
          echo "Stale stage marker: $setup_stage" >&2
        fi
      fi
      slim_pipeline="$genome_dir/$genome/Pipeline/run_elm.pip"
      slim_stage="$slim_pipeline/run_elm.stage"
      if [[ -d "$slim_pipeline" ]]; then
        if grep -q "Pipeline complete" "$slim_stage" 2>/dev/null; then
          echo "Step 4a is already complete for $genome."
          exit 0
        fi
        if (( reset_slim == 0 )); then
          echo "An incomplete step 4a controller already exists: $slim_pipeline" >&2
          echo "Confirm that no run_elm jobs are active, then rerun with --reset-slim." >&2
          exit 1
        fi
        slim_backup="${slim_pipeline}.incomplete.$(date +%Y%m%d_%H%M%S)"
        echo "Backing up incomplete step 4a controller to: $slim_backup"
        run mv "$slim_pipeline" "$slim_backup"

        # Controller state is separate from per-target method state.  Remove
        # stale scheduling markers so methods with missing outputs are queued
        # again; completed outputs are detected before these markers are used.
        id_list="$genome_dir/$genome/fasta/id_list"
        while IFS= read -r target; do
          [[ -n "$target" ]] || continue
          for method in FindMotifs_ELM FindPRDs_ELM Gopher MuscleG MotifConsv ProtPeptide_ELM; do
            method_dir="$genome_dir/$genome/Pipeline/Pipeline_$target/$method"
            run rm -f "$method_dir/done" "$method_dir/process"
          done
        done < "$id_list"
      fi
      echo "[Step 4a] Running PrePPI-SLiM protein-peptide pipeline"
      run_elm_args=("$slim_dir/SCR/run_elm.pl" "$genome")
      (( debug_mode == 0 )) || run_elm_args+=(-d)
      run "${run_elm_args[@]}"
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

echo "Pipeline commands completed. Submitted SLURM jobs may still be running."
