#!/usr/bin/env python3
"""Python launcher for the PrePPI-SLiM HPC pipeline."""

from __future__ import annotations

import argparse
import glob
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time


CONDA_ENV = Path("/groups/bh6_gp/software/conda_envs/v2")
CONDA_PYTHON = CONDA_ENV / "bin" / "python3"
DEFAULT_BN_FILE = Path(
    "/groups/bh6_gp/as7656/research/training_PrePPI/protein_peptide/"
    "human_AF_bn_training/test_006/motif_elm.lr"
)


def build_parser() -> argparse.ArgumentParser:
    steps = """Steps:
  1  Set up the genome and run IUPred
  2  Annotate each protein with motifs, PRDs, and conservation
  3  Enumerate compatible PRD-SLiM pairs
  4  Calculate likelihood ratios from pair-candidate CSV.gz files
  5  Consolidate directional LR results under Interactions
"""
    parser = argparse.ArgumentParser(
        description="Run one PrePPI-SLiM pipeline step.",
        epilog=steps,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--interactive", action="store_true",
        help="run the step-aware interactive setup wizard",
    )
    parser.add_argument("-g", "--genome", help="primary/anchor genome folder")
    parser.add_argument("-x", "--genome2", help="partner genome")
    parser.add_argument(
        "-f", "--fasta", type=Path,
        help="input FASTA (default: input.fasta beside this launcher)",
    )
    parser.add_argument(
        "-s", "--step", "--steps", type=int, choices=(1, 2, 3, 4, 5),
        help="one pipeline step to run",
    )
    parser.add_argument(
        "-n", "--max-sequences", type=int, default=0,
        help="use only the first N FASTA records in step 1",
    )
    parser.add_argument(
        "--orientation", choices=("motif", "prd", "both"), default="both",
        help="pairing orientation for steps 3 and 4 (default: both)",
    )
    parser.add_argument(
        "-b", "--bn-file", type=Path, default=DEFAULT_BN_FILE,
        help=f"reference LR table (default: {DEFAULT_BN_FILE})",
    )
    parser.add_argument("-i", "--pair-input", help="step-3 CSV.gz filename")
    parser.add_argument(
        "-o", "--lr-output", default="prd_slim_LR.csv.gz",
        help="per-query step-4 output filename",
    )
    parser.add_argument(
        "--consolidated-output",
        help="step-5 filename under <genome>/Interactions",
    )
    parser.add_argument("--batch", action="store_true")
    parser.add_argument("--skip-health-check", action="store_true")
    parser.add_argument("--debug", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--reset-step", action="store_true")
    parser.add_argument("--reset-setup", action="store_true")
    parser.add_argument(
        "--reset-annotation", "--reset-slim", dest="reset_annotation",
        action="store_true",
    )
    parser.add_argument("--reset-pairing", action="store_true")
    return parser


def activate_required_environment() -> None:
    """Re-execute under the requested conda environment without prompting."""
    if not CONDA_PYTHON.is_file() or not os.access(CONDA_PYTHON, os.X_OK):
        raise SystemExit(
            "Required conda environment is unavailable.\n"
            f"Environment: {CONDA_ENV}\n"
            f"Expected Python executable: {CONDA_PYTHON}"
        )
    try:
        current_python = Path(sys.executable).resolve()
        required_python = CONDA_PYTHON.resolve()
    except OSError as error:
        raise SystemExit(
            f"Cannot inspect the required conda environment: {error}"
        ) from error
    if current_python == required_python:
        return

    environment = os.environ.copy()
    environment["CONDA_PREFIX"] = str(CONDA_ENV)
    environment["CONDA_DEFAULT_ENV"] = str(CONDA_ENV)
    environment["PATH"] = (
        f"{CONDA_ENV / 'bin'}:{environment.get('PATH', '')}"
    )
    try:
        os.execve(
            str(CONDA_PYTHON),
            [str(CONDA_PYTHON), str(Path(__file__).resolve()), *sys.argv[1:]],
            environment,
        )
    except OSError as error:
        raise SystemExit(
            f"Failed to start required conda environment {CONDA_ENV}: {error}"
        ) from error


def prompt(text: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default is not None else ""
    answer = input(f"{text}{suffix}: ").strip()
    return answer or (default or "")


def yes_no(text: str, default: bool = False) -> bool:
    suffix = "[Y/n]" if default else "[y/N]"
    answer = input(f"{text} {suffix} ").strip().lower()
    if not answer:
        return default
    return answer in {"y", "yes"}


def configure_interactively(args: argparse.Namespace, script_dir: Path) -> None:
    if not args.genome:
        args.genome = prompt("Primary/anchor genome")
    if not args.genome:
        raise SystemExit("Genome name cannot be empty.")

    if args.step is None:
        print("\nAvailable PrePPI-SLiM steps:")
        print("  1  Set up the genome and run IUPred")
        print("  2  Annotate motifs, PRDs, orthologs, and conservation")
        print("  3  Enumerate compatible PRD-SLiM pairs")
        print("  4  Calculate protein-pair likelihood ratios")
        print("  5  Consolidate directional LR results under Interactions")
        selected = prompt("Select step number")
        if selected not in {"1", "2", "3", "4", "5"}:
            raise SystemExit(f"Invalid step: {selected}")
        args.step = int(selected)

    print(f"\nRequired run settings for step {args.step}:")
    if args.step == 1:
        selected_fasta = prompt("Input FASTA", "input.fasta")
        args.fasta = Path(selected_fasta)
        if not args.fasta.is_absolute():
            args.fasta = script_dir / args.fasta
    elif args.step == 2:
        print("  No additional required settings.")
    elif args.step in (3, 4):
        args.genome2 = prompt("Partner genome", args.genome2 or args.genome)
        label = (
            "Orientation: motif, prd, or both"
            if args.step == 3 else "Orientation used in step 3"
        )
        selected_orientation = prompt(label, args.orientation)
        if selected_orientation not in {"motif", "prd", "both"}:
            raise SystemExit("Orientation must be motif, prd, or both.")
        args.orientation = selected_orientation
        if args.step == 4:
            args.bn_file = Path(prompt("Motif LR reference file", str(args.bn_file)))
    else:
        args.genome2 = prompt("Partner genome", args.genome2 or args.genome)
        print("  No additional required settings.")

    print(f"\nOptional settings for step {args.step}:")
    if args.step == 1:
        print("  --max-sequences N  limit FASTA records (default: all)")
    elif args.step == 3:
        print("  --skip-health-check  bypass per-protein input validation")
    elif args.step == 4:
        print("  --pair-input NAME  override the derived step-3 CSV.gz")
        print(f"  --lr-output NAME   output filename (default: {args.lr_output})")
        print("  --batch            process matching batch genome folders")
        print("  --bn-file FILE     override the default reference LR table")
    elif args.step == 5:
        print(f"  --lr-output NAME   per-query input (default: {args.lr_output})")
        print("  --consolidated-output NAME  override the final filename")
        print("  --batch            read matching batch genome folders")
    print("  --debug, --dry-run, --reset-step")

    if yes_no("Configure optional settings?"):
        if args.step == 1:
            maximum = prompt(
                "Maximum FASTA records, 0 for all", str(args.max_sequences)
            )
            try:
                args.max_sequences = int(maximum)
            except ValueError as error:
                raise SystemExit(
                    "Maximum FASTA records must be an integer."
                ) from error
        elif args.step == 3:
            args.skip_health_check = yes_no(
                "Skip the annotation health check?", args.skip_health_check
            )
        elif args.step == 4:
            pair_input = prompt(
                "Pair-input filename", args.pair_input or "automatically derived"
            )
            args.pair_input = None if pair_input == "automatically derived" else pair_input
            args.lr_output = prompt("LR-output filename", args.lr_output)
            args.batch = yes_no("Use batch mode?", args.batch)
        elif args.step == 5:
            args.lr_output = prompt("Per-query LR filename", args.lr_output)
            default_name = consolidated_output_name(args)
            args.consolidated_output = prompt(
                "Consolidated output filename",
                args.consolidated_output or default_name,
            )
            args.batch = yes_no("Use batch mode?", args.batch)
        args.debug = yes_no(
            "Retain per-task scheduler logs (--debug)?", args.debug
        )
        args.dry_run = yes_no(
            "Print commands without submitting (--dry-run)?", args.dry_run
        )
        args.reset_step = yes_no(
            "Undo this step instead of running it (--reset-step)?",
            args.reset_step,
        )

    args.genome2 = args.genome2 or args.genome
    print("\nRun summary:")
    print(f"  Genome:      {args.genome}")
    print(f"  Step:        {args.step}")
    if args.step == 1:
        print(f"  Input FASTA: {args.fasta}")
    if args.step in (3, 4, 5):
        print(f"  Partner:     {args.genome2}")
    if args.step in (3, 4):
        print(f"  Orientation: {args.orientation}")
    if args.step == 4:
        print(f"  LR table:    {args.bn_file}")
    if args.step == 5:
        print(
            f"  Final file:  {args.consolidated_output or consolidated_output_name(args)}"
        )
    if args.reset_step:
        print("  Action:      reset only")
    if args.dry_run:
        print("  Mode:        dry run")
    if not yes_no("Continue?", True):
        raise SystemExit("Cancelled.")


def validate(args: argparse.Namespace, script_dir: Path) -> None:
    args.fasta = args.fasta or script_dir / "input.fasta"
    args.genome2 = args.genome2 or args.genome
    if args.max_sequences < 0:
        raise SystemExit("--max-sequences must be a non-negative integer.")
    for genome in (args.genome, args.genome2):
        if (
            not genome
            or genome in {".", ".."}
            or not re.fullmatch(r"[A-Za-z0-9_.-]+", genome)
        ):
            raise SystemExit(f"Unsafe genome name: {genome}")
    if args.reset_step and (
        args.reset_setup or args.reset_annotation or args.reset_pairing
    ):
        raise SystemExit(
            "--reset-step cannot be combined with incomplete-controller resets."
        )
    if args.consolidated_output and (
        "/" in args.consolidated_output
        or args.consolidated_output in {".", ".."}
    ):
        raise SystemExit(
            "--consolidated-output must be a filename, not a path."
        )


def consolidated_output_name(args: argparse.Namespace) -> str:
    if args.genome == args.genome2:
        return f"{args.genome}_PrePPI_SLiM_LR.csv.gz"
    return f"{args.genome}_vs_{args.genome2}_PrePPI_SLiM_LR.csv.gz"


class Pipeline:
    """Execute and safely reset the five PrePPI-SLiM pipeline steps."""

    annotation_methods = (
        "FindMotifs_ELM", "FindPRDs_ELM", "Gopher", "MuscleG", "MotifConsv",
    )

    def __init__(self, args: argparse.Namespace, script_dir: Path) -> None:
        self.args = args
        self.script_dir = script_dir
        self.slim_dir = script_dir.parent
        self.genome_dir = Path(os.environ.get(
            "HFPD_DATA_DIR",
            "/groups/bh6_gp/data/shares/databases/hfpd/genomes",
        ))
        self.genome = args.genome
        self.genome2 = args.genome2
        self.reset_backup_root: Path | None = None
        self.reset_moved = 0

        os.environ["HFPD_DIR"] = str(self.slim_dir)
        os.environ["HFPD_DATA_DIR"] = str(self.genome_dir)
        old_perl5lib = os.environ.get("PERL5LIB")
        os.environ["PERL5LIB"] = (
            f"{self.slim_dir}:{old_perl5lib}"
            if old_perl5lib else str(self.slim_dir)
        )
        os.environ["PERL_PERTURB_KEYS"] = "0"
        os.environ["PERL_HASH_SEED"] = "0"

    def run(self, *command: object) -> None:
        argv = [str(item) for item in command]
        print("+", shlex.join(argv), flush=True)
        if not self.args.dry_run:
            subprocess.run(argv, check=True)

    @staticmethod
    def safe_name(value: str) -> str:
        return re.sub(r"[^A-Za-z0-9_.-]", "_", value)

    @staticmethod
    def complete(stage_file: Path) -> bool:
        try:
            return "Pipeline complete" in stage_file.read_text(errors="replace")
        except OSError:
            return False

    def genome_home(self, genome: str | None = None) -> Path:
        return self.genome_dir / (genome or self.genome)

    def targets(self, home: Path) -> list[str]:
        id_list = home / "fasta" / "id_list"
        try:
            targets = [
                line.strip() for line in id_list.read_text().splitlines()
                if line.strip()
            ]
            if targets:
                return targets
        except OSError:
            pass
        seqs = home / "Seqs"
        if not seqs.is_dir():
            return []
        return sorted(path.name for path in seqs.iterdir() if path.is_dir())

    def pair_archive_name(self, role: str | None = None) -> str:
        role = role or self.args.orientation
        if role == "both" and self.genome != self.genome2:
            return self.safe_name(
                f"{self.genome}_vs_{self.genome2}_prd_slim_candidates.csv.gz"
            )
        if role == "motif":
            motif_genome, prd_genome = self.genome, self.genome2
        else:
            motif_genome, prd_genome = self.genome2, self.genome
        return self.safe_name(
            f"{motif_genome}_slim_{prd_genome}_prd_candidates.csv.gz"
        )

    def consolidated_output_path(self) -> Path:
        filename = (
            self.args.consolidated_output or consolidated_output_name(self.args)
        )
        return self.genome_home() / "Interactions" / filename

    def verify_disorder(self, genome: str) -> None:
        home = self.genome_home(genome)
        targets = self.targets(home)
        if not targets:
            raise SystemExit(
                f"Target list is missing or empty: {home / 'fasta/id_list'}"
            )
        missing = []
        for target in targets:
            disorder = home / "Seqs" / target / "disorder.fa"
            if not disorder.is_file() or disorder.stat().st_size == 0:
                missing.append(target)
                print(
                    f"Missing IUPred output: {genome}/Seqs/{target}/disorder.fa",
                    file=sys.stderr,
                )
        if missing:
            raise SystemExit(1)
        print(f"Verified IUPred output for {len(targets)} target(s) in {genome}.")

    @staticmethod
    def any_exists(*paths: Path) -> bool:
        return any(path.exists() for path in paths)

    def verify_annotations(self, genome: str, role: str) -> None:
        home = self.genome_home(genome)
        targets = self.targets(home)
        if not targets:
            raise SystemExit(
                f"Target list is missing or empty: {home / 'fasta/id_list'}"
            )
        missing: list[str] = []
        missing_conservation = 0
        for target in targets:
            seq = home / "Seqs" / target
            motifs = seq / "Motifs"
            if role in {"motif", "both"}:
                if not (seq / "disorder.fa").exists():
                    missing.append(f"{target}/disorder.fa")
                if not self.any_exists(
                    motifs / "slim_candidates.csv", motifs / "motif_elm.txt",
                ):
                    missing.append(f"{target}/Motifs/slim_candidates.csv")
                if not self.any_exists(
                    motifs / "conserved_slims.csv", motifs / "motif_elm.csv",
                ):
                    missing_conservation += 1
            if role in {"prd", "both"} and not self.any_exists(
                motifs / "prd_candidates.csv", motifs / "prd_elm.txt",
            ):
                missing.append(f"{target}/Motifs/prd_candidates.csv")

        for item in missing[:10]:
            print(
                f"Missing required {role}-side annotation: "
                f"{genome}/Seqs/{item}", file=sys.stderr,
            )
        if len(missing) > 10:
            print(
                f"... and {len(missing) - 10} additional required file(s) "
                "are missing.", file=sys.stderr,
            )
        if missing_conservation:
            print(
                f"Note: {missing_conservation} of {len(targets)} protein(s) in "
                f"{genome} lack conservation output; their motifs will use "
                "conserved=0."
            )
        if missing:
            raise SystemExit(1)
        print(
            f"Verified {role} annotation inputs for {len(targets)} protein(s) "
            f"in {genome}."
        )

    def controller_active(self, controller_dir: Path, job_name: str) -> bool:
        if shutil.which("squeue") is None:
            return False
        by_name = subprocess.run(
            ["squeue", "-h", "-n", job_name],
            capture_output=True, text=True, check=False,
        )
        if by_name.stdout.strip():
            return True
        running = controller_dir / "running"
        try:
            lines = running.read_text().splitlines()
        except OSError:
            return False
        for line in lines:
            fields = line.split()
            if not fields:
                continue
            by_id = subprocess.run(
                ["squeue", "-h", "-j", fields[-1]],
                capture_output=True, text=True, check=False,
            )
            if by_id.stdout.strip():
                return True
        return False

    def genome_has_active_jobs(self, home: Path, genome: str) -> bool:
        for controller in (home / "Pipeline").glob("*.pip"):
            if self.controller_active(controller, f"{controller.stem}.{genome}"):
                print(f"Active pipeline controller: {controller.stem}", file=sys.stderr)
                return True
        lr_controller = home / "Pipeline" / "PrP_LR"
        if self.controller_active(lr_controller, f"PrP_LR_{genome}"):
            print(f"Active LR controller: PrP_LR_{genome}", file=sys.stderr)
            return True
        return False

    def begin_backup(self, home: Path, step: int) -> None:
        stamp = time.strftime("%Y%m%d_%H%M%S")
        self.reset_backup_root = (
            home / "Reset" / f"step_{step}_{stamp}_{os.getpid()}"
        )
        self.reset_moved = 0

    def backup_item(self, home: Path, source: Path) -> None:
        if not source.exists() and not source.is_symlink():
            return
        try:
            relative = source.relative_to(home)
        except ValueError as error:
            raise SystemExit(
                f"Refusing to reset path outside the genome: {source}"
            ) from error
        if self.reset_backup_root is None:
            raise RuntimeError("Reset backup was not initialized")
        destination = self.reset_backup_root / relative
        self.run("mkdir", "-p", destination.parent)
        self.run("mv", source, destination)
        self.reset_moved += 1

    def remove_markers(self, method_dir: Path) -> None:
        self.run("rm", "-f", method_dir / "done", method_dir / "process")

    def reset_step2(self, home: Path) -> None:
        controller = home / "Pipeline" / "run_elm.pip"
        if self.controller_active(controller, f"run_elm.{self.genome}"):
            raise SystemExit(
                "Cannot reset step 2 while its SLURM jobs are active."
            )
        self.backup_item(home, controller)
        for target in self.targets(home):
            pipeline = home / "Pipeline" / f"Pipeline_{target}"
            for method in self.annotation_methods:
                self.backup_item(home, pipeline / method)
            seq = home / "Seqs" / target
            for relative in (
                "Motifs/slim_candidates.csv",
                "Motifs/prd_candidates.csv",
                "Motifs/conserved_slims.csv",
                "Motifs/motif_elm.txt",
                "Motifs/prd_elm.txt",
                f"Motifs/{target}.pfam",
                "Motifs/motif_elm.csv",
                "Orthology/gopher.fas",
                "Orthology/gopher.ort",
                "Aligns/residue_conservation.csv",
                "Aligns/Gopher.csv",
            ):
                self.backup_item(home, seq / relative)

    def reset_pair_orientation(self, home: Path, role: str) -> None:
        run_tag = f"{role}_{self.safe_name(self.genome2)}"
        pipeline_name = f"ProtPeptide_ELM_{run_tag}"
        controller = home / "Pipeline" / f"{pipeline_name}.pip"
        if self.controller_active(controller, f"{pipeline_name}.{self.genome}"):
            raise SystemExit(
                f"Cannot reset step 3 while its SLURM jobs are active: "
                f"{pipeline_name}"
            )
        self.backup_item(home, controller)
        archive = self.pair_archive_name(role)
        for target in self.targets(home):
            self.backup_item(
                home,
                home / "Pipeline" / f"Pipeline_{target}" /
                "ProtPeptide_ELM" / run_tag,
            )
            motifs = home / "Seqs" / target / "Motifs"
            self.backup_item(home, motifs / archive)
            if role == "motif":
                self.backup_item(
                    home, motifs /
                    f"{self.genome}_slim_{self.genome2}_prd_ProtPeptide_ELM.txt.tar.gz",
                )
                legacy = (
                    "ProtPeptide_ELM.txt.tar.gz"
                    if self.genome == self.genome2
                    else f"{self.genome2}_ProtPeptide_ELM.txt.tar.gz"
                )
                self.backup_item(home, motifs / legacy)
            elif role == "prd":
                self.backup_item(
                    home, motifs /
                    f"{self.genome2}_slim_{self.genome}_prd_ProtPeptide_ELM.txt.tar.gz",
                )
                legacy = (
                    "reverse_ProtPeptide_ELM.txt.tar.gz"
                    if self.genome == self.genome2
                    else f"{self.genome2}_reverse_ProtPeptide_ELM.txt.tar.gz"
                )
                self.backup_item(home, motifs / legacy)

    def reset_step4_home(self, home: Path) -> None:
        controller = home / "Pipeline" / "PrP_LR"
        if self.controller_active(controller, f"PrP_LR_{home.name}"):
            raise SystemExit(
                f"Cannot reset step 4 while its SLURM job is active for "
                f"{home.name}."
            )
        self.begin_backup(home, 4)
        self.backup_item(home, controller)
        for target in self.targets(home):
            self.backup_item(
                home, home / "Seqs" / target / "Motifs" / self.args.lr_output,
            )
        if self.reset_moved:
            print(f"Step 4 reset for {home.name}. Backup: {self.reset_backup_root}")
        else:
            print(f"Step 4 was already absent for {home.name}.")

    def reset_selected_step(self) -> None:
        home = self.genome_home()
        if (self.args.step != 4 or not self.args.batch) and not home.is_dir():
            print(
                f"Genome/run does not exist; step {self.args.step} is already "
                f"absent: {home}"
            )
            return
        if self.args.step == 1:
            if self.genome_has_active_jobs(home, self.genome):
                raise SystemExit(
                    "Cannot reset step 1 while jobs belonging to this genome "
                    "are active."
                )
            backup = home.with_name(
                f"{home.name}.reset_step_1_{time.strftime('%Y%m%d_%H%M%S')}_"
                f"{os.getpid()}"
            )
            self.run("mv", home, backup)
            print(f"Step 1 reset. The entire genome/run was moved to: {backup}")
        elif self.args.step == 2:
            self.begin_backup(home, 2)
            self.reset_step2(home)
            if self.reset_moved:
                print(f"Step 2 reset. Backup: {self.reset_backup_root}")
            else:
                print(f"Step 2 was already absent for {self.genome}.")
        elif self.args.step == 3:
            self.begin_backup(home, 3)
            role = self.args.orientation
            if self.genome == self.genome2 and role == "both":
                role = "motif"
            roles = ("both", "motif", "prd") if role == "both" else (role,)
            for selected_role in roles:
                run_tag = f"{selected_role}_{self.safe_name(self.genome2)}"
                controller = home / "Pipeline" / f"ProtPeptide_ELM_{run_tag}.pip"
                if self.controller_active(
                    controller, f"ProtPeptide_ELM_{run_tag}.{self.genome}",
                ):
                    raise SystemExit(
                        "Cannot reset step 3 while its SLURM jobs are active: "
                        f"ProtPeptide_ELM_{run_tag}"
                    )
            for selected_role in roles:
                self.reset_pair_orientation(home, selected_role)
            if self.reset_moved:
                print(
                    f"Step 3 reset for {self.genome} versus {self.genome2} "
                    f"({role}).\nBackup: {self.reset_backup_root}"
                )
            else:
                print("The selected step 3 comparison was already absent.")
        elif self.args.step == 4:
            if "/" in self.args.lr_output or self.args.lr_output in {".", ".."}:
                raise SystemExit(
                    "--lr-output must be a filename when resetting step 4."
                )
            homes = (
                [Path(path) for path in sorted(glob.glob(
                    str(self.genome_dir / f"{self.genome}_batch*"))
                )]
                if self.args.batch else [home]
            )
            if not homes:
                raise SystemExit(
                    f"No batch genome folders found for {self.genome}_batch*."
                )
            for batch_home in homes:
                controller = batch_home / "Pipeline" / "PrP_LR"
                if self.controller_active(controller, f"PrP_LR_{batch_home.name}"):
                    raise SystemExit(
                        f"Cannot reset step 4 while its SLURM job is active for "
                        f"{batch_home.name}. No batch was reset."
                    )
            for batch_home in homes:
                self.reset_step4_home(batch_home)
        else:
            self.begin_backup(home, 5)
            self.backup_item(home, self.consolidated_output_path())
            if self.reset_moved:
                print(f"Step 5 reset. Backup: {self.reset_backup_root}")
            else:
                print("The selected consolidated output was already absent.")

    def run_pair_orientation(self, role: str) -> None:
        run_tag = f"{role}_{self.safe_name(self.genome2)}"
        pipeline_name = f"ProtPeptide_ELM_{run_tag}"
        controller = (
            self.genome_home() / "Pipeline" / f"{pipeline_name}.pip"
        )
        stage = controller / f"{pipeline_name}.stage"
        if controller.is_dir():
            if self.complete(stage):
                print(
                    f"Pairing orientation '{role}' is already complete for "
                    f"{self.genome} versus {self.genome2}."
                )
                return
            if not self.args.reset_pairing:
                raise SystemExit(
                    f"An incomplete pairing controller exists: {controller}\n"
                    "Confirm its jobs are inactive, then use --reset-pairing."
                )
            backup = controller.with_name(
                f"{controller.name}.incomplete.{time.strftime('%Y%m%d_%H%M%S')}"
            )
            print(f"Backing up incomplete pairing controller to: {backup}")
            self.run("mv", controller, backup)
            for target in self.targets(self.genome_home()):
                self.remove_markers(
                    self.genome_home() / "Pipeline" / f"Pipeline_{target}" /
                    "ProtPeptide_ELM" / run_tag
                )
        command: list[object] = [
            self.slim_dir / "SCR" / "run_PrP_ELM_batches.pl",
            self.genome, "--genome2", self.genome2, "--orientation", role,
        ]
        if self.args.debug:
            command.append("--debug")
        self.run(*command)

    def step1(self) -> None:
        fasta = self.args.fasta
        if not fasta.is_file() or not os.access(fasta, os.R_OK):
            raise SystemExit(f"FASTA file is not readable: {fasta}")
        prepared = fasta
        temporary: Path | None = None
        try:
            if self.args.max_sequences:
                temp_root = Path(os.environ.get("TMPDIR", "/tmp"))
                if not temp_root.is_dir() or not os.access(temp_root, os.W_OK):
                    print(
                        f"Temporary directory is unavailable: {temp_root}; "
                        "using /tmp instead.", file=sys.stderr,
                    )
                    temp_root = Path("/tmp")
                with tempfile.NamedTemporaryFile(
                    mode="w", prefix="preppi_slim_fasta.",
                    dir=temp_root, delete=False,
                ) as output, fasta.open() as source:
                    temporary = Path(output.name)
                    record_count = 0
                    found_record = False
                    for line in source:
                        if line.startswith(">"):
                            if record_count >= self.args.max_sequences:
                                break
                            record_count += 1
                            found_record = True
                        output.write(line)
                if not found_record:
                    raise SystemExit(f"No FASTA records found in {fasta}")
                prepared = temporary
                print(
                    f"Small-run input: first {self.args.max_sequences} FASTA "
                    f"record(s) from {fasta}"
                )
            controller = self.genome_home() / "Pipeline" / "Setup.pip"
            stage = controller / "Setup.stage"
            if controller.is_dir():
                if self.complete(stage):
                    print(f"Step 1 is already complete for {self.genome}.")
                    return
                if not self.args.reset_setup:
                    raise SystemExit(
                        f"An incomplete step 1 controller exists: {controller}\n"
                        "Confirm its jobs are inactive, then use --reset-setup."
                    )
                backup = controller.with_name(
                    f"{controller.name}.incomplete."
                    f"{time.strftime('%Y%m%d_%H%M%S')}"
                )
                self.run("mv", controller, backup)
            print("[Step 1] Setting up the genome and running IUPred")
            self.run(
                self.slim_dir / "SCR" / "setup_genome.pl",
                self.genome, "-f", prepared,
            )
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)

    def step2(self) -> None:
        if not self.args.dry_run:
            self.verify_disorder(self.genome)
        controller = self.genome_home() / "Pipeline" / "run_elm.pip"
        stage = controller / "run_elm.stage"
        if controller.is_dir():
            if self.complete(stage):
                print(f"Step 2 is already complete for {self.genome}.")
                return
            if not self.args.reset_annotation:
                raise SystemExit(
                    f"An incomplete step 2 controller exists: {controller}\n"
                    "Confirm its jobs are inactive, then use --reset-annotation."
                )
            backup = controller.with_name(
                f"{controller.name}.incomplete.{time.strftime('%Y%m%d_%H%M%S')}"
            )
            self.run("mv", controller, backup)
            for target in self.targets(self.genome_home()):
                for method in self.annotation_methods:
                    self.remove_markers(
                        self.genome_home() / "Pipeline" /
                        f"Pipeline_{target}" / method
                    )
        print("[Step 2] Annotating motifs, PRDs, orthologs, and conservation")
        command: list[object] = [
            self.slim_dir / "SCR" / "run_elm.pl", self.genome,
        ]
        if self.args.debug:
            command.append("-d")
        self.run(*command)

    def step3(self) -> None:
        role = self.args.orientation
        if self.genome == self.genome2 and role == "both":
            print(
                "The two orientations are equivalent for a self-proteome "
                "search; running motif orientation once."
            )
            role = "motif"
            self.args.orientation = role
        if not self.args.dry_run and not self.args.skip_health_check:
            if role == "motif":
                self.verify_annotations(self.genome, "motif")
                self.verify_annotations(self.genome2, "prd")
            elif role == "prd":
                self.verify_annotations(self.genome, "prd")
                self.verify_annotations(self.genome2, "motif")
            else:
                self.verify_annotations(self.genome, "both")
                self.verify_annotations(self.genome2, "both")
        elif self.args.skip_health_check:
            print(
                "Warning: skipping per-protein annotation checks before step 3.",
                file=sys.stderr,
            )
        print("[Step 3] Enumerating compatible PRD-SLiM pairs")
        self.run_pair_orientation(role)

    def step4(self) -> None:
        if not self.args.bn_file.is_file():
            raise SystemExit(
                f"Motif LR reference file does not exist: {self.args.bn_file}"
            )
        pair_input = self.args.pair_input or self.pair_archive_name()
        if "/" in pair_input or pair_input in {".", ".."}:
            raise SystemExit("--pair-input must be a filename, not a path.")
        print("[Step 4] Calculating protein-peptide likelihood ratios")
        self.run(
            CONDA_PYTHON, self.slim_dir / "SCR" / "run_PrP_LR.py",
            "-g", self.genome,
            "-batch", str(self.args.batch),
            "-i", pair_input,
            "-b", self.args.bn_file,
            "-o", self.args.lr_output,
        )

    def step5(self) -> None:
        output = self.consolidated_output_path()
        print("[Step 5] Consolidating directional likelihood-ratio results")
        self.run(
            CONDA_PYTHON, self.slim_dir / "SCR" / "consolidate_PrP_LR.py",
            "--base-dir", self.genome,
            "--batch", str(self.args.batch),
            "--lr-filename", self.args.lr_output,
            "--output", output,
            "--mode", "max",
        )

    def execute(self) -> None:
        print(f"Primary/anchor genome: {self.genome}")
        print(f"Partner genome: {self.genome2}")
        print(f"PrePPI-SLiM code: {self.slim_dir}")
        if self.args.reset_step:
            self.reset_selected_step()
            print("Reset completed. The selected step was not rerun.")
            return
        if self.args.step == 1:
            self.step1()
        elif self.args.step == 2:
            self.step2()
        elif self.args.step == 3:
            self.step3()
        elif self.args.step == 4:
            self.step4()
        else:
            self.step5()
        print("Pipeline command completed. Submitted SLURM jobs may still be running.")


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    args = build_parser().parse_args()
    activate_required_environment()
    if args.interactive or not args.genome or args.step is None:
        configure_interactively(args, script_dir)
    validate(args, script_dir)

    print(f"Conda environment: {CONDA_ENV}")
    Pipeline(args, script_dir).execute()


if __name__ == "__main__":
    main()
