#!/usr/bin/env python3
"""Local tests for the Python-only PrePPI-SLiM runtime."""
from __future__ import annotations

import csv
import gzip
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import MODS.Genome as genome_module
from MODS.ELM import elm_definitions, motif_matches
from MODS.Genome import Genome, target_ids, uniprot_mapping
from MODS.IUPRED import IUPRED, IUPRED_EXECUTABLE
from MODS.Pipeline import Pipeline
from MODS.ProtPeptide_ELM import ProtPeptide_ELM


class PythonRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        genome_module.GENOME_DIRECTORY = self.root

    def tearDown(self):
        self.temporary.cleanup()

    def create_genome(self, name, fasta_text):
        fasta = self.root / f"{name}.fasta"
        fasta.write_text(fasta_text)
        genome = Genome(gname=name)
        genome.init(fasta, mk_tgt_dirs="yes")
        return genome

    def write_annotations(self, genome, protein, motif=None, prd=None):
        base = Path(genome.seqd(protein), "Motifs")
        if motif:
            (base / "slim_candidates.csv").write_text(
                "# record_type=ELM_SLIM_candidates\n"
                f"# genome={genome.gname}\tprotein={protein}\n"
                "elm_class,motif_sequence,motif_start,motif_end\n"
                + motif + "\n"
            )
            (base / "conserved_slims.csv").write_text(
                "elm_class,motif_sequence,motif_start\n"
                + ",".join(motif.split(",")[:3]) + "\n"
            )
            Path(genome.seqd(protein), "disorder.fa").write_text(
                ">disorder\n" + "D" * 20 + "\n"
            )
        if prd:
            (base / "prd_candidates.csv").write_text(
                "# record_type=ELM_peptide_recognition_domains\n"
                f"# genome={genome.gname}\tprotein={protein}\n"
                "elm_class,pfam_domain,prd_start,prd_end\n"
                + prd + "\n"
            )

    def test_genome_layout_and_stable_hfpd_id(self):
        genome = self.create_genome(
            "query", ">sp|P12345|TEST_HUMAN\nACDE\n"
            ">HFPD_123456;sp|Q9TEST|SECOND_HUMAN\nFGHI\n"
            ">HFPD_123457.c1;tr|A0A1234567|DOMAIN_HUMAN\nKLM\n",
        )
        self.assertEqual(
            genome.get_target_list(), ["000001", "123456", "123457.c1"],
        )
        with Path(genome.home, "seqs.csv").open(newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(
            tuple(rows[0]),
            ("HFPD_ID", "UniProt_ID", "Description", "Sequence", "Length", "Source"),
        )
        self.assertEqual(rows[0]["UniProt_ID"], "P12345")
        self.assertEqual(rows[0]["Length"], "4")
        self.assertEqual(rows[0]["Source"], "Full-length")
        self.assertEqual(rows[2]["Source"], "CDD")
        self.assertEqual(
            uniprot_mapping(genome.home)["123457.c1"], "A0A1234567",
        )
        self.assertFalse(Path(genome.home, "fasta").exists())
        self.assertTrue(Path(genome.home, "Interactions").is_dir())
        self.assertTrue(Path(genome.seqd("000001"), "Pipeline").is_symlink())
        self.assertFalse(Path(genome.seqd("000001"), "Models").exists())

    def test_legacy_fasta_genome_remains_readable(self):
        home = self.root / "legacy"
        fasta = home / "fasta"
        fasta.mkdir(parents=True)
        (fasta / "id_list").write_text("000001\n000002.c1\n")
        (fasta / "map_list").write_text(
            "000001\t>P99999\n000002.c1\t>Q88888\n"
        )
        (fasta / "000001").write_text(
            ">HFPD_000001;sp|P99999|LEGACY_HUMAN old protein\nACDE\n"
        )
        (fasta / "000002.c1").write_text(
            ">HFPD_000002.c1;legacy domain\nFGH\n"
        )
        genome = Genome(gname="legacy")
        self.assertEqual(target_ids(home), ["000001", "000002.c1"])
        self.assertEqual(genome.seq("000001"), "ACDE")
        self.assertEqual(genome.desc("000002.c1"), "HFPD_000002.c1;legacy domain")
        self.assertEqual(
            uniprot_mapping(home),
            {"000001": "P99999", "000002.c1": "Q88888"},
        )

    def test_elm_scanner_keeps_overlapping_hits(self):
        definitions = self.root / "elm.tsv"
        definitions.write_text(
            "Accession\tELMIdentifier\tDescription\tRegex\tProbability\t"
            "Instances\tInstanceLogic\tInteractionDomainId\n"
            "x\tLIG_TEST\tx\tA.A\tx\tx\tx\tSH3_1\n"
        )
        records = elm_definitions(definitions)
        self.assertEqual(
            motif_matches("AAAAA", records),
            [("LIG_TEST", "AAA", 1, 3), ("LIG_TEST", "AAA", 2, 4), ("LIG_TEST", "AAA", 3, 5)],
        )

    def test_iupred_invokes_the_executable_not_its_class(self):
        genome = self.create_genome(
            "iupred_test",
            ">sp|P12345|TEST_HUMAN\nACDE\n",
        )
        method = IUPRED(gname=genome.gname, gid="000001")
        result = type(
            "Result",
            (),
            {"stdout": "1 A 0.75\n2 C 0.25\n3 D 0.80\n4 E 0.10\n"},
        )()
        observed = {}

        def fake_execute(command, **_kwargs):
            observed["fasta"] = Path(command[1]).read_text()
            observed["path"] = Path(command[1])
            return result

        with patch.object(method, "execute", side_effect=fake_execute) as execute:
            method.run()
        command = execute.call_args.args[0]
        self.assertEqual(command[0], IUPRED_EXECUTABLE)
        self.assertNotIsInstance(command[0], type)
        self.assertIn(">HFPD_000001;sp|P12345|TEST_HUMAN", observed["fasta"])
        self.assertFalse(observed["path"].exists())
        self.assertEqual(
            Path(method.output).read_text().splitlines()[1],
            "D-D-",
        )

    def test_pfam_scan_does_not_depend_on_removed_perl_globals(self):
        slim_root = Path(__file__).resolve().parents[1]
        files = (
            slim_root / "SCR/PfamScan/pfam_scan.pl",
            slim_root / "MODS/Bio/Pfam/Scan/PfamScan.pm",
        )
        for path in files:
            self.assertNotIn("MODS::Globals", path.read_text())

    def test_pairing_both_preserves_direction_and_prd_name(self):
        anchor = self.create_genome("anchor", ">sp|A00001|A_HUMAN\nAAAAAAAAAA\n")
        partner = self.create_genome("partner", ">sp|B00001|B_HUMAN\nBBBBBBBBBB\n")
        self.write_annotations(anchor, "000001", motif="LIG_TEST,AAA,1,3", prd="LIG_TEST,AnchorDomain,4,8")
        self.write_annotations(partner, "000001", motif="LIG_TEST,BBB,2,4", prd="LIG_TEST,PartnerDomain,5,9")
        method = ProtPeptide_ELM(
            gname="anchor", gid="000001",
            step_parameters={"external": "partner", "orientation": "both", "run_tag": "both_partner"},
        )
        method.run()
        with gzip.open(method.output, "rt") as handle:
            data = [line for line in handle if not line.startswith("#")]
        rows = list(csv.DictReader(data))
        self.assertEqual(len(rows), 2)
        self.assertEqual({row["anchor_role"] for row in rows}, {"motif", "prd"})
        self.assertEqual({row["prd_name"] for row in rows}, {"AnchorDomain", "PartnerDomain"})

    def test_pairing_accepts_legacy_headerless_partner_annotations(self):
        anchor = self.create_genome("anchor", ">sp|A00001|A_HUMAN\nAAAAAAAAAA\n")
        partner = self.create_genome("legacy", ">sp|B00001|B_HUMAN\nBBBBBBBBBB\n")
        self.write_annotations(
            anchor, "000001",
            motif="LIG_TEST,AAA,1,3",
            prd="LIG_TEST,AnchorDomain,4,8",
        )
        motifs = Path(partner.seqd("000001"), "Motifs")
        (motifs / "motif_elm.txt").write_text("LIG_TEST\tBBB\t2\t4\n")
        (motifs / "motif_elm.csv").write_text("LIG_TEST\tBBB\t2\n")
        (motifs / "prd_elm.txt").write_text("LIG_TEST\tLegacyDomain\t5\t9\n")
        Path(partner.seqd("000001"), "disorder.fa").write_text(">disorder\n" + "D" * 20 + "\n")

        method = ProtPeptide_ELM(
            gname="anchor", gid="000001",
            step_parameters={"external": "legacy", "orientation": "both", "run_tag": "both_legacy"},
        )
        method.run()
        with gzip.open(method.output, "rt") as handle:
            rows = list(csv.DictReader(line for line in handle if not line.startswith("#")))
        self.assertEqual(len(rows), 2)
        self.assertEqual({row["anchor_role"] for row in rows}, {"motif", "prd"})
        self.assertEqual({row["prd_name"] for row in rows}, {"AnchorDomain", "LegacyDomain"})

    @patch("MODS.Pipeline.subprocess.run")
    def test_generated_jobs_use_python_runtime_and_afterany_cleanup(self, run):
        run.side_effect = [
            type("Result", (), {"stdout": "Submitted batch job 101\n"})(),
            type("Result", (), {"stdout": "Submitted batch job 102\n"})(),
        ]
        genome = self.create_genome("jobs", ">sp|P12345|TEST_HUMAN\nACDE\n")
        pipeline = Pipeline(name="Setup", gname="jobs")
        Path(pipeline.stepsfn).write_text("")
        pipeline.add_step("IUPRED")
        record = pipeline.qsub_block("IUPRED_test1.tgt", "IUPRED", 1)
        self.assertEqual(record, "IUPRED_test1.tgt\t102")
        batch = Path(pipeline.pipedir, "IUPRED_test1.tgt.batch1.sh").read_text()
        waiter = Path(pipeline.pipedir, "wIUPRED_test1.tgt.sh").read_text()
        self.assertIn("run_method.py", batch)
        self.assertNotIn("run_method.pl", batch)
        self.assertIn("--dependency=afterany:101", waiter)
        self.assertIn("process_method.py", waiter)


if __name__ == "__main__":
    unittest.main()
