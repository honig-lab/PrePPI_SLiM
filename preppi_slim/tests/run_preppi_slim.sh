#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  run_preppi_slim.sh [options]

Core options:
      --interactive          Run the step-aware interactive setup wizard
  -g, --genome NAME          Primary/anchor genome folder
  -f, --fasta FILE           Input FASTA for step 1
                             (default: input.fasta beside this launcher)
  -s, --step STEP            One step to run (prompted if omitted)
  -n, --max-sequences N      Use only the first N FASTA records in step 1
      --debug                Retain per-task SLURM output and error logs
      --dry-run              Print commands without submitting them

Pairing options for step 3:
  -x, --genome2 NAME         Partner genome (default: primary genome)
      --orientation ROLE     motif, prd, or both (default: both)
                             motif: primary supplies SLiMs
                             prd:   primary supplies PRDs
                             both:  run both, storing both under primary
      --skip-health-check    Skip the per-protein step-3 input scan

LR options for step 4:
  -b, --bn-file FILE         Bayesian-network CSV
  -i, --pair-input NAME      Step-3 per-query CSV.gz (derived if omitted)
  -o, --lr-output NAME       Per-query LR CSV (default: prd_slim_LR.csv.gz)
      --batch                Treat --genome as a batch basename

Reset options:
      --reset-step           Undo the selected step, save a recoverable backup,
                             and exit without rerunning the step
      --reset-setup          Back up and replace incomplete step 1 state
      --reset-annotation     Back up and replace incomplete step 2 state
      --reset-slim           Alias for --reset-annotation
      --reset-pairing        Back up and replace incomplete step 3 state

Steps:
  1   Set up the genome and run IUPred
  2   Annotate each protein with motifs, PRDs, and conservation
  3   Enumerate compatible PRD-SLiM pairs
  4   Calculate likelihood ratios from pair-candidate CSV.gz files

Examples:
  ./run_preppi_slim.sh -g test -f proteins.fa -n 10 -s 1
  ./run_preppi_slim.sh -g test -s 2
  ./run_preppi_slim.sh -g proteome_A -x proteome_B -s 3 --orientation both
  ./run_preppi_slim.sh -g test -s 3 --reset-step
EOF
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
slim_dir=$(cd -- "$script_dir/.." && pwd)
genome_dir="${HFPD_DATA_DIR:-/groups/bh6_gp/data/shares/databases/hfpd/genomes}"
fasta_file="$script_dir/input.fasta"
genome=""
genome2=""
orientation="both"
user_step=""
max_sequences=0
bn_file=""
pair_input=""
lr_output="prd_slim_LR.csv.gz"
batch_mode="False"
reset_setup=0
reset_annotation=0
reset_pairing=0
reset_step=0
skip_health_check=0
debug_mode=0
dry_run=0
interactive_mode=0
force_interactive=0

ask_yes_no() {
  local prompt=$1 default=${2:-n} answer suffix
  if [[ "$default" == "y" ]]; then
    suffix="[Y/n]"
  else
    suffix="[y/N]"
  fi
  read -r -p "$prompt $suffix " answer
  answer=${answer:-$default}
  [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

while (( $# > 0 )); do
  case "$1" in
    -g|--genome) genome=${2:?"Missing value for $1"}; shift 2 ;;
    -x|--genome2) genome2=${2:?"Missing value for $1"}; shift 2 ;;
    -f|--fasta) fasta_file=${2:?"Missing value for $1"}; shift 2 ;;
    -s|--step|--steps) user_step=${2:?"Missing value for $1"}; shift 2 ;;
    -n|--max-sequences) max_sequences=${2:?"Missing value for $1"}; shift 2 ;;
    -b|--bn-file) bn_file=${2:?"Missing value for $1"}; shift 2 ;;
    -i|--pair-input) pair_input=${2:?"Missing value for $1"}; shift 2 ;;
    -o|--lr-output) lr_output=${2:?"Missing value for $1"}; shift 2 ;;
    --orientation) orientation=${2:?"Missing value for $1"}; shift 2 ;;
    --batch) batch_mode="True"; shift ;;
    --reset-setup) reset_setup=1; shift ;;
    --reset-annotation|--reset-slim) reset_annotation=1; shift ;;
    --reset-pairing) reset_pairing=1; shift ;;
    --reset-step) reset_step=1; shift ;;
    --skip-health-check) skip_health_check=1; shift ;;
    --debug) debug_mode=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    --interactive) force_interactive=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$genome" ]]; then
  interactive_mode=1
  read -r -p "Primary/anchor genome: " genome
fi
[[ -n "$genome" ]] || { echo "Genome name cannot be empty." >&2; exit 2; }

if [[ -z "$user_step" ]]; then
  interactive_mode=1
  printf '\nAvailable PrePPI-SLiM steps:\n'
  printf '  1  Set up the genome and run IUPred\n'
  printf '  2  Annotate motifs, PRDs, orthologs, and conservation\n'
  printf '  3  Enumerate compatible PRD-SLiM pairs\n'
  printf '  4  Calculate protein-pair likelihood ratios\n'
  read -r -p "Select step number: " user_step
fi
(( force_interactive == 0 )) || interactive_mode=1
read -r -a selected_steps <<< "$user_step"
(( ${#selected_steps[@]} == 1 )) || {
  echo "Run exactly one step at a time." >&2
  exit 2
}
step=${selected_steps[0]}
case "$step" in
  1|2|3|4) ;;
  *) echo "Invalid step: $step" >&2; exit 2 ;;
esac

if (( interactive_mode == 1 )); then
  printf '\nRequired run settings for step %s:\n' "$step"
  case "$step" in
    1)
      read -r -p "Input FASTA [input.fasta]: " interactive_value
      if [[ -n "$interactive_value" ]]; then
        fasta_file=$interactive_value
      fi
      ;;
    2)
      echo "  No additional required settings."
      ;;
    3)
      read -r -p "Partner genome [$genome]: " interactive_value
      genome2=${interactive_value:-${genome2:-$genome}}
      read -r -p "Orientation: motif, prd, or both [$orientation]: " interactive_value
      orientation=${interactive_value:-$orientation}
      ;;
    4)
      read -r -p "Partner genome [$genome]: " interactive_value
      genome2=${interactive_value:-${genome2:-$genome}}
      read -r -p "Orientation used in step 3 [$orientation]: " interactive_value
      orientation=${interactive_value:-$orientation}
      while [[ -z "$bn_file" ]]; do
        read -r -p "Bayesian-network CSV: " bn_file
      done
      ;;
  esac

  printf '\nOptional settings for step %s:\n' "$step"
  case "$step" in
    1)
      printf '  --max-sequences N  limit the FASTA records (default: all)\n'
      ;;
    3)
      printf '  --skip-health-check  bypass per-protein input validation\n'
      ;;
    4)
      printf '  --pair-input NAME  override the derived step-3 CSV.gz\n'
      printf '  --lr-output NAME   output filename (default: %s)\n' "$lr_output"
      printf '  --batch            process matching batch genome folders\n'
      ;;
  esac
  printf '  --debug, --dry-run, --reset-step\n'

  if ask_yes_no "Configure optional settings?" n; then
    case "$step" in
      1)
        read -r -p "Maximum FASTA records, 0 for all [$max_sequences]: " interactive_value
        max_sequences=${interactive_value:-$max_sequences}
        ;;
      3)
        if ask_yes_no "Skip the annotation health check?" "$([[ $skip_health_check == 1 ]] && echo y || echo n)"; then
          skip_health_check=1
        else
          skip_health_check=0
        fi
        ;;
      4)
        read -r -p "Pair-input filename [automatically derived]: " interactive_value
        pair_input=${interactive_value:-$pair_input}
        read -r -p "LR-output filename [$lr_output]: " interactive_value
        lr_output=${interactive_value:-$lr_output}
        if ask_yes_no "Use batch mode?" "$([[ $batch_mode == True ]] && echo y || echo n)"; then
          batch_mode=True
        else
          batch_mode=False
        fi
        ;;
    esac
    if ask_yes_no "Retain per-task scheduler logs (--debug)?" "$([[ $debug_mode == 1 ]] && echo y || echo n)"; then
      debug_mode=1
    else
      debug_mode=0
    fi
    if ask_yes_no "Print commands without submitting (--dry-run)?" "$([[ $dry_run == 1 ]] && echo y || echo n)"; then
      dry_run=1
    else
      dry_run=0
    fi
    if ask_yes_no "Undo this step instead of running it (--reset-step)?" "$([[ $reset_step == 1 ]] && echo y || echo n)"; then
      reset_step=1
    else
      reset_step=0
    fi
  fi

  genome2=${genome2:-$genome}
  printf '\nRun summary:\n'
  printf '  Genome:      %s\n' "$genome"
  printf '  Step:        %s\n' "$step"
  [[ "$step" == "1" ]] && printf '  Input FASTA: %s\n' "$fasta_file"
  if [[ "$step" == "3" || "$step" == "4" ]]; then
    printf '  Partner:     %s\n' "$genome2"
    printf '  Orientation: %s\n' "$orientation"
  fi
  [[ "$step" == "4" ]] && printf '  BN file:     %s\n' "$bn_file"
  (( reset_step == 0 )) || printf '  Action:      reset only\n'
  (( dry_run == 0 )) || printf '  Mode:        dry run\n'
  if ! ask_yes_no "Continue?" y; then
    echo "Cancelled."
    exit 0
  fi
fi

genome2=${genome2:-$genome}
[[ "$max_sequences" =~ ^[0-9]+$ ]] || {
  echo "--max-sequences must be a non-negative integer." >&2
  exit 2
}
case "$orientation" in
  motif|prd|both) ;;
  *) echo "--orientation must be motif, prd, or both." >&2; exit 2 ;;
esac
for genome_name in "$genome" "$genome2"; do
  [[ "$genome_name" =~ ^[A-Za-z0-9_.-]+$ && "$genome_name" != "." && "$genome_name" != ".." ]] || {
    echo "Unsafe genome name: $genome_name" >&2
    exit 2
  }
done

if (( reset_step == 1 && (reset_setup == 1 || reset_annotation == 1 || reset_pairing == 1) )); then
  echo "--reset-step cannot be combined with the incomplete-controller reset options." >&2
  exit 2
fi

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

if [[ "$step" == "1" && "$reset_step" == "0" ]]; then
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

echo "Primary/anchor genome: $genome"
echo "Partner genome: $genome2"
echo "PrePPI-SLiM code: $slim_dir"

verify_disorder() {
  local gname=$1 id_list target missing=0 count=0
  id_list="$genome_dir/$gname/fasta/id_list"
  [[ -s "$id_list" ]] || { echo "Target list is missing or empty: $id_list" >&2; return 1; }
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    (( count += 1 ))
    if [[ ! -s "$genome_dir/$gname/Seqs/$target/disorder.fa" ]]; then
      echo "Missing IUPred output: $gname/Seqs/$target/disorder.fa" >&2
      missing=1
    fi
  done < "$id_list"
  (( missing == 0 )) || return 1
  echo "Verified IUPred output for $count target(s) in $gname."
}

verify_annotations() {
  local gname=$1 role=$2 id_list target file
  local missing=0 missing_conservation=0 checked=0 reported=0
  id_list="$genome_dir/$gname/fasta/id_list"
  [[ -s "$id_list" ]] || { echo "Target list is missing or empty: $id_list" >&2; return 1; }
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    (( checked += 1 ))
    if [[ "$role" == "motif" || "$role" == "both" ]]; then
      file="$genome_dir/$gname/Seqs/$target/disorder.fa"
      if [[ ! -e "$file" ]]; then
        (( missing += 1 ))
        if (( reported < 10 )); then
          echo "Missing required motif-side annotation: $file" >&2
          (( reported += 1 ))
        fi
      fi
      if [[ ! -e "$genome_dir/$gname/Seqs/$target/Motifs/slim_candidates.csv" &&
            ! -e "$genome_dir/$gname/Seqs/$target/Motifs/motif_elm.txt" ]]; then
        (( missing += 1 ))
        if (( reported < 10 )); then
          echo "Missing required motif-side annotation: $gname/Seqs/$target/Motifs/slim_candidates.csv (or legacy motif_elm.txt)" >&2
          (( reported += 1 ))
        fi
      fi
      if [[ ! -e "$genome_dir/$gname/Seqs/$target/Motifs/conserved_slims.csv" &&
            ! -e "$genome_dir/$gname/Seqs/$target/Motifs/motif_elm.csv" ]]; then
        (( missing_conservation += 1 ))
      fi
    fi
    if [[ "$role" == "prd" || "$role" == "both" ]]; then
      if [[ ! -e "$genome_dir/$gname/Seqs/$target/Motifs/prd_candidates.csv" &&
            ! -e "$genome_dir/$gname/Seqs/$target/Motifs/prd_elm.txt" ]]; then
        (( missing += 1 ))
        if (( reported < 10 )); then
          echo "Missing required PRD-side annotation: $gname/Seqs/$target/Motifs/prd_candidates.csv (or legacy prd_elm.txt)" >&2
          (( reported += 1 ))
        fi
      fi
    fi
  done < "$id_list"
  if (( missing_conservation > 0 )); then
    echo "Note: $missing_conservation of $checked protein(s) in $gname lack conserved_slims.csv (or legacy motif_elm.csv); their motifs will use conserved=0."
  fi
  if (( missing > reported )); then
    echo "... and $((missing - reported)) additional required annotation file(s) are missing." >&2
  fi
  (( missing == 0 )) || return 1
  echo "Verified $role annotation inputs for $checked protein(s) in $gname."
}

safe_name() {
  printf '%s' "$1" | sed 's/[^A-Za-z0-9_.-]/_/g'
}

controller_is_active() {
  local controller_dir=$1 job_name=$2 job_id
  command -v squeue >/dev/null 2>&1 || return 1

  if squeue -h -n "$job_name" 2>/dev/null | grep -q .; then
    return 0
  fi
  if [[ -f "$controller_dir/running" ]]; then
    while read -r job_id; do
      [[ -n "$job_id" ]] || continue
      if squeue -h -j "$job_id" 2>/dev/null | grep -q .; then
        return 0
      fi
    done < <(awk 'NF { print $NF }' "$controller_dir/running")
  fi
  return 1
}

genome_has_active_jobs() {
  local genome_home=$1 genome_name=$2 controller_dir controller_name
  shopt -s nullglob
  reset_controllers=("$genome_home"/Pipeline/*.pip)
  shopt -u nullglob
  for controller_dir in "${reset_controllers[@]}"; do
    controller_name=$(basename "$controller_dir" .pip)
    if controller_is_active "$controller_dir" "${controller_name}.${genome_name}"; then
      echo "Active pipeline controller: $controller_name" >&2
      return 0
    fi
  done
  if controller_is_active "$genome_home/Pipeline/PrP_LR" "PrP_LR_${genome_name}"; then
    echo "Active LR controller: PrP_LR_${genome_name}" >&2
    return 0
  fi
  return 1
}

reset_backup_root=""
reset_moved=0

begin_reset_backup() {
  local genome_home=$1 selected_step=$2 stamp
  stamp=$(date +%Y%m%d_%H%M%S)
  reset_backup_root="$genome_home/Reset/step_${selected_step}_${stamp}_$$"
  reset_moved=0
}

backup_item() {
  local genome_home=$1 source=$2 relative destination
  [[ -e "$source" || -L "$source" ]] || return 0
  case "$source" in
    "$genome_home"/*) relative=${source#"$genome_home"/} ;;
    *) echo "Refusing to reset path outside the genome: $source" >&2; return 1 ;;
  esac
  destination="$reset_backup_root/$relative"
  run mkdir -p "$(dirname "$destination")"
  run mv "$source" "$destination"
  (( reset_moved += 1 ))
}

load_targets() {
  local genome_home=$1 target_dir
  reset_targets=()
  if [[ -s "$genome_home/fasta/id_list" ]]; then
    while IFS= read -r target; do
      [[ -n "$target" ]] && reset_targets+=("$target")
    done < "$genome_home/fasta/id_list"
  elif [[ -d "$genome_home/Seqs" ]]; then
    for target_dir in "$genome_home"/Seqs/*; do
      [[ -d "$target_dir" ]] && reset_targets+=("$(basename "$target_dir")")
    done
  fi
}

pair_archive_name() {
  local role=$1 motif_genome prd_genome archive
  if [[ "$role" == "both" && "$genome" != "$genome2" ]]; then
    archive="${genome}_vs_${genome2}_prd_slim_candidates.csv.gz"
    safe_name "$archive"
    return
  fi
  if [[ "$role" == "motif" ]]; then
    motif_genome=$genome
    prd_genome=$genome2
  else
    motif_genome=$genome2
    prd_genome=$genome
  fi
  archive="${motif_genome}_slim_${prd_genome}_prd_candidates.csv.gz"
  safe_name "$archive"
}

reset_pair_orientation() {
  local role=$1 genome_home=$2 safe_partner run_tag pipeline_name pipeline_dir archive target method_dir
  safe_partner=$(safe_name "$genome2")
  run_tag="${role}_${safe_partner}"
  pipeline_name="ProtPeptide_ELM_${run_tag}"
  pipeline_dir="$genome_home/Pipeline/${pipeline_name}.pip"

  if controller_is_active "$pipeline_dir" "${pipeline_name}.${genome}"; then
    echo "Cannot reset step 3 while its SLURM jobs are active: $pipeline_name" >&2
    echo "Wait for them to finish or cancel them explicitly, then retry." >&2
    return 1
  fi

  archive=$(pair_archive_name "$role")
  backup_item "$genome_home" "$pipeline_dir"
  for target in "${reset_targets[@]}"; do
    method_dir="$genome_home/Pipeline/Pipeline_$target/ProtPeptide_ELM/$run_tag"
    backup_item "$genome_home" "$method_dir"
    backup_item "$genome_home" "$genome_home/Seqs/$target/Motifs/$archive"

    # Remove an equivalent archive created by an older launcher version.
    if [[ "$role" == "motif" ]]; then
      backup_item "$genome_home" "$genome_home/Seqs/$target/Motifs/${genome}_slim_${genome2}_prd_ProtPeptide_ELM.txt.tar.gz"
      if [[ "$genome" == "$genome2" ]]; then
        backup_item "$genome_home" "$genome_home/Seqs/$target/Motifs/ProtPeptide_ELM.txt.tar.gz"
      else
        backup_item "$genome_home" "$genome_home/Seqs/$target/Motifs/${genome2}_ProtPeptide_ELM.txt.tar.gz"
      fi
    elif [[ "$role" == "prd" ]]; then
      backup_item "$genome_home" "$genome_home/Seqs/$target/Motifs/${genome2}_slim_${genome}_prd_ProtPeptide_ELM.txt.tar.gz"
      if [[ "$genome" == "$genome2" ]]; then
        backup_item "$genome_home" "$genome_home/Seqs/$target/Motifs/reverse_ProtPeptide_ELM.txt.tar.gz"
      else
        backup_item "$genome_home" "$genome_home/Seqs/$target/Motifs/${genome2}_reverse_ProtPeptide_ELM.txt.tar.gz"
      fi
    fi
  done
}

reset_step_2() {
  local genome_home=$1 controller_dir target method file
  controller_dir="$genome_home/Pipeline/run_elm.pip"
  if controller_is_active "$controller_dir" "run_elm.${genome}"; then
    echo "Cannot reset step 2 while its SLURM jobs are active." >&2
    echo "Wait for them to finish or cancel them explicitly, then retry." >&2
    return 1
  fi

  backup_item "$genome_home" "$controller_dir"
  for target in "${reset_targets[@]}"; do
    for method in FindMotifs_ELM FindPRDs_ELM Gopher MuscleG MotifConsv; do
      backup_item "$genome_home" "$genome_home/Pipeline/Pipeline_$target/$method"
    done
    for file in \
      "$genome_home/Seqs/$target/Motifs/slim_candidates.csv" \
      "$genome_home/Seqs/$target/Motifs/prd_candidates.csv" \
      "$genome_home/Seqs/$target/Motifs/conserved_slims.csv" \
      "$genome_home/Seqs/$target/Motifs/motif_elm.txt" \
      "$genome_home/Seqs/$target/Motifs/prd_elm.txt" \
      "$genome_home/Seqs/$target/Motifs/$target.pfam" \
      "$genome_home/Seqs/$target/Motifs/motif_elm.csv" \
      "$genome_home/Seqs/$target/Orthology/gopher.fas" \
      "$genome_home/Seqs/$target/Orthology/gopher.ort" \
      "$genome_home/Seqs/$target/Aligns/residue_conservation.csv" \
      "$genome_home/Seqs/$target/Aligns/Gopher.csv"
    do
      backup_item "$genome_home" "$file"
    done
  done
}

reset_step_4_home() {
  local genome_home=$1 batch_name controller_dir target
  batch_name=$(basename "$genome_home")
  controller_dir="$genome_home/Pipeline/PrP_LR"
  if controller_is_active "$controller_dir" "PrP_LR_${batch_name}"; then
    echo "Cannot reset step 4 while its SLURM job is active for $batch_name." >&2
    echo "Wait for it to finish or cancel it explicitly, then retry." >&2
    return 1
  fi
  begin_reset_backup "$genome_home" 4
  load_targets "$genome_home"
  backup_item "$genome_home" "$controller_dir"
  for target in "${reset_targets[@]}"; do
    backup_item "$genome_home" "$genome_home/Seqs/$target/Motifs/$lr_output"
  done
  if (( reset_moved > 0 )); then
    echo "Step 4 reset for $batch_name. Backup: $reset_backup_root"
  else
    echo "Step 4 was already absent for $batch_name."
  fi
}

reset_selected_step() {
  local genome_home="$genome_dir/$genome" backup role batch_home batch_name
  local safe_partner run_tag pipeline_name pipeline_dir
  local -a reset_roles
  if [[ "$step" != "4" || "$batch_mode" != "True" ]]; then
    [[ -d "$genome_home" ]] || {
      echo "Genome/run does not exist; step $step is already absent: $genome_home"
      return 0
    }
  fi

  case "$step" in
    1)
      if genome_has_active_jobs "$genome_home" "$genome"; then
        echo "Cannot reset step 1 while jobs belonging to this genome are active." >&2
        echo "Wait for them to finish or cancel them explicitly, then retry." >&2
        return 1
      fi
      backup="${genome_home}.reset_step_1_$(date +%Y%m%d_%H%M%S)_$$"
      run mv "$genome_home" "$backup"
      echo "Step 1 reset. The entire genome/run was moved to: $backup"
      ;;
    2)
      begin_reset_backup "$genome_home" 2
      load_targets "$genome_home"
      reset_step_2 "$genome_home"
      if (( reset_moved > 0 )); then
        echo "Step 2 reset. Backup: $reset_backup_root"
      else
        echo "Step 2 was already absent for $genome."
      fi
      ;;
    3)
      begin_reset_backup "$genome_home" 3
      load_targets "$genome_home"
      if [[ "$genome" == "$genome2" && "$orientation" == "both" ]]; then
        orientation=motif
      fi
      if [[ "$orientation" == "both" ]]; then
        reset_roles=(both motif prd)
      else
        reset_roles=("$orientation")
      fi
      for role in "${reset_roles[@]}"; do
        safe_partner=$(safe_name "$genome2")
        run_tag="${role}_${safe_partner}"
        pipeline_name="ProtPeptide_ELM_${run_tag}"
        pipeline_dir="$genome_home/Pipeline/${pipeline_name}.pip"
        if controller_is_active "$pipeline_dir" "${pipeline_name}.${genome}"; then
          echo "Cannot reset step 3 while its SLURM jobs are active: $pipeline_name" >&2
          echo "Wait for them to finish or cancel them explicitly, then retry." >&2
          return 1
        fi
      done
      for role in "${reset_roles[@]}"; do
        reset_pair_orientation "$role" "$genome_home"
      done
      if (( reset_moved > 0 )); then
        echo "Step 3 reset for $genome versus $genome2 ($orientation)."
        echo "Backup: $reset_backup_root"
      else
        echo "The selected step 3 comparison was already absent."
      fi
      ;;
    4)
      [[ "$lr_output" != */* && "$lr_output" != "." && "$lr_output" != ".." ]] || {
        echo "--lr-output must be a filename, not a path, when resetting step 4." >&2
        return 1
      }
      if [[ "$batch_mode" == "True" ]]; then
        shopt -s nullglob
        reset_batch_homes=("$genome_dir/${genome}_batch"*)
        shopt -u nullglob
        if (( ${#reset_batch_homes[@]} == 0 )); then
          echo "No batch genome folders found for ${genome}_batch*." >&2
          return 1
        fi
        for batch_home in "${reset_batch_homes[@]}"; do
          batch_name=$(basename "$batch_home")
          if controller_is_active "$batch_home/Pipeline/PrP_LR" "PrP_LR_${batch_name}"; then
            echo "Cannot reset step 4 while its SLURM job is active for $batch_name." >&2
            echo "No batch was reset. Wait for it to finish or cancel it explicitly." >&2
            return 1
          fi
        done
        for batch_home in "${reset_batch_homes[@]}"; do
          reset_step_4_home "$batch_home"
        done
      else
        reset_step_4_home "$genome_home"
      fi
      ;;
    *)
      echo "Invalid step: $step" >&2
      return 2
      ;;
  esac
}

run_pair_orientation() {
  local role=$1 safe_partner run_tag pipeline_name pipeline_dir pipeline_stage backup id_list target method_dir
  safe_partner=$(safe_name "$genome2")
  run_tag="${role}_${safe_partner}"
  pipeline_name="ProtPeptide_ELM_${run_tag}"
  pipeline_dir="$genome_dir/$genome/Pipeline/${pipeline_name}.pip"
  pipeline_stage="$pipeline_dir/${pipeline_name}.stage"

  if [[ -d "$pipeline_dir" ]]; then
    if grep -q "Pipeline complete" "$pipeline_stage" 2>/dev/null; then
      echo "Pairing orientation '$role' is already complete for $genome versus $genome2."
      return
    fi
    if (( reset_pairing == 0 )); then
      echo "An incomplete pairing controller exists: $pipeline_dir" >&2
      echo "Confirm its jobs are inactive, then use --reset-pairing." >&2
      return 1
    fi
    backup="${pipeline_dir}.incomplete.$(date +%Y%m%d_%H%M%S)"
    echo "Backing up incomplete pairing controller to: $backup"
    run mv "$pipeline_dir" "$backup"
    id_list="$genome_dir/$genome/fasta/id_list"
    while IFS= read -r target; do
      [[ -n "$target" ]] || continue
      method_dir="$genome_dir/$genome/Pipeline/Pipeline_$target/ProtPeptide_ELM/$run_tag"
      run rm -f "$method_dir/done" "$method_dir/process"
    done < "$id_list"
  fi

  pair_args=("$slim_dir/SCR/run_PrP_ELM_batches.pl" "$genome" --genome2 "$genome2" --orientation "$role")
  (( debug_mode == 0 )) || pair_args+=(--debug)
  run "${pair_args[@]}"
}

if (( reset_step == 1 )); then
  reset_selected_step
  echo "Reset completed. The selected step was not rerun."
  exit 0
fi

case "$step" in
  1)
    setup_dir="$genome_dir/$genome/Pipeline/Setup.pip"
    setup_stage="$setup_dir/Setup.stage"
    if [[ -d "$setup_dir" ]]; then
      if grep -q "Pipeline complete" "$setup_stage" 2>/dev/null; then
        echo "Step 1 is already complete for $genome."
        exit 0
      fi
      if (( reset_setup == 0 )); then
        echo "An incomplete step 1 controller exists: $setup_dir" >&2
        echo "Confirm its jobs are inactive, then use --reset-setup." >&2
        exit 1
      fi
      setup_backup="${setup_dir}.incomplete.$(date +%Y%m%d_%H%M%S)"
      run mv "$setup_dir" "$setup_backup"
    fi
    echo "[Step 1] Setting up the genome and running IUPred"
    run "$slim_dir/SCR/setup_genome.pl" "$genome" -f "$prepared_fasta"
    ;;

  2)
    (( dry_run == 1 )) || verify_disorder "$genome"
    annotation_dir="$genome_dir/$genome/Pipeline/run_elm.pip"
    annotation_stage="$annotation_dir/run_elm.stage"
    if [[ -d "$annotation_dir" ]]; then
      if grep -q "Pipeline complete" "$annotation_stage" 2>/dev/null; then
        echo "Step 2 is already complete for $genome."
        exit 0
      fi
      if (( reset_annotation == 0 )); then
        echo "An incomplete step 2 controller exists: $annotation_dir" >&2
        echo "Confirm its jobs are inactive, then use --reset-annotation." >&2
        exit 1
      fi
      annotation_backup="${annotation_dir}.incomplete.$(date +%Y%m%d_%H%M%S)"
      run mv "$annotation_dir" "$annotation_backup"
      id_list="$genome_dir/$genome/fasta/id_list"
      while IFS= read -r target; do
        [[ -n "$target" ]] || continue
        for method in FindMotifs_ELM FindPRDs_ELM Gopher MuscleG MotifConsv; do
          method_dir="$genome_dir/$genome/Pipeline/Pipeline_$target/$method"
          run rm -f "$method_dir/done" "$method_dir/process"
        done
      done < "$id_list"
    fi
    echo "[Step 2] Annotating motifs, PRDs, orthologs, and conservation"
    annotation_args=("$slim_dir/SCR/run_elm.pl" "$genome")
    (( debug_mode == 0 )) || annotation_args+=(-d)
    run "${annotation_args[@]}"
    ;;

  3)
    if [[ "$genome" == "$genome2" && "$orientation" == "both" ]]; then
      echo "The two orientations are equivalent for a self-proteome search; running motif orientation once."
      orientation=motif
    fi
    if (( dry_run == 0 && skip_health_check == 0 )); then
      case "$orientation" in
        motif)
          verify_annotations "$genome" motif
          verify_annotations "$genome2" prd
          ;;
        prd)
          verify_annotations "$genome" prd
          verify_annotations "$genome2" motif
          ;;
        both)
          verify_annotations "$genome" both
          verify_annotations "$genome2" both
          ;;
      esac
    elif (( skip_health_check == 1 )); then
      echo "Warning: skipping per-protein annotation checks before step 3." >&2
    fi
    echo "[Step 3] Enumerating compatible PRD-SLiM pairs"
    if [[ "$orientation" == "both" ]]; then
      run_pair_orientation both
    elif [[ "$orientation" == "motif" ]]; then
      run_pair_orientation motif
    else
      run_pair_orientation prd
    fi
    ;;

  4)
    if [[ -z "$bn_file" ]]; then
      read -r -p "Path to Bayesian-network CSV: " bn_file
    fi
    [[ -f "$bn_file" ]] || { echo "BN file does not exist: $bn_file" >&2; exit 1; }
    if [[ -z "$pair_input" ]]; then
      pair_input=$(pair_archive_name "$orientation")
    fi
    [[ "$pair_input" != */* ]] || { echo "--pair-input must be a filename, not a path." >&2; exit 2; }
    echo "[Step 4] Calculating protein-peptide likelihood ratios"
    run python3 "$slim_dir/SCR/run_PrP_LR.py" \
      -g "$genome" -batch "$batch_mode" -i "$pair_input" \
      -b "$bn_file" -o "$lr_output"
    ;;

  *)
    echo "Invalid step: $step" >&2
    exit 2
    ;;
esac

echo "Pipeline command completed. Submitted SLURM jobs may still be running."
