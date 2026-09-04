#!/usr/bin/env python3
"""Synthetic tests for consolidated, concurrent pipeline status CSV files."""

from concurrent.futures import ProcessPoolExecutor
import csv
from pathlib import Path
import tempfile
import unittest

from MODS.PipelineState import StatusTable


def concurrent_update(arguments):
    status_path, hfpd_id, output_path = arguments
    output = Path(output_path)
    output.write_text(hfpd_id)
    table = StatusTable(status_path, ["metric"])
    table.start(hfpd_id, "worker", [output])
    table.finish(
        hfpd_id,
        "worker",
        elapsed_seconds=int(hfpd_id),
        expected_outputs=[output],
        metric=int(hfpd_id) * 2,
    )


class PipelineStateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.status_path = (
            self.root / "Pipeline" / "Synthetic.pip" / "status.csv"
        )

    def tearDown(self):
        self.temporary.cleanup()

    def rows(self):
        with self.status_path.open(newline="", encoding="utf-8") as handle:
            return list(csv.DictReader(handle))

    def test_rows_are_sorted_and_outputs_are_health_checked(self):
        table = StatusTable(self.status_path)
        table.initialize([
            {"hfpd_id": "020525.200_248", "subtask_id": "MotifConsv"},
            {"hfpd_id": "000002", "subtask_id": "MotifConsv"},
        ])
        output = self.root / "conserved_slims.csv"
        output.write_text("elm_class\n")
        table.start("020525.200_248", "MotifConsv", [output])
        table.finish(
            "020525.200_248",
            "MotifConsv",
            elapsed_seconds=1.25,
            expected_outputs=[output],
        )
        rows = self.rows()
        self.assertEqual(
            [row["hfpd_id"] for row in rows],
            ["000002", "020525.200_248"],
        )
        self.assertEqual(rows[1]["status"], "completed")
        self.assertEqual(rows[1]["health"], "healthy")
        self.assertEqual(rows[1]["output_count"], "1")
        self.assertEqual(rows[1]["elapsed_seconds"], "1.250")

    def test_missing_expected_output_is_a_failure(self):
        table = StatusTable(self.status_path)
        missing = self.root / "missing.csv.gz"
        table.finish("000001", "PrP_LR", expected_outputs=[missing])
        row = self.rows()[0]
        self.assertEqual(row["status"], "failed")
        self.assertEqual(row["health"], "missing_output")
        self.assertIn("missing.csv.gz", row["missing_outputs"])

    def test_initialization_reopens_stale_completed_row(self):
        table = StatusTable(self.status_path)
        output = self.root / "result.csv.gz"
        output.write_text("result")
        table.finish("000001", "PrP_LR", expected_outputs=[output])
        output.unlink()
        table.initialize([{
            "hfpd_id": "000001",
            "subtask_id": "PrP_LR",
            "status": "pending",
            "health": "pending",
            "expected_outputs": f'["{output}"]',
            "outputs_complete": "no",
        }])
        row = self.rows()[0]
        self.assertEqual(row["status"], "pending")
        self.assertEqual(row["health"], "pending")
        self.assertEqual(row["outputs_complete"], "no")

    def test_worker_waits_for_postprocessing_before_completion(self):
        table = StatusTable(self.status_path)
        output = self.root / "prd_candidates.csv"
        output.write_text("elm_class\n")
        table.start("000001", "FindPRDs_ELM", [output])
        table.ready_for_postprocess(
            "000001",
            "FindPRDs_ELM",
            elapsed_seconds=2.5,
            expected_outputs=[output],
        )
        self.assertEqual(self.rows()[0]["status"], "awaiting_postprocess")
        self.assertFalse(table.all_terminal_and_healthy())
        table.finish("000001", "FindPRDs_ELM", expected_outputs=[output])
        self.assertTrue(table.all_terminal_and_healthy())

    def test_skipped_no_work_task_is_healthy(self):
        table = StatusTable(self.status_path)
        table.skip("000001", "FindMotifs_ELM", "No candidate motifs.")
        row = self.rows()[0]
        self.assertEqual(row["status"], "skipped")
        self.assertEqual(row["health"], "not_applicable")
        self.assertTrue(table.all_terminal_and_healthy())

    def test_parallel_workers_do_not_lose_rows(self):
        table = StatusTable(self.status_path, ["metric"])
        ids = [f"{index:06d}" for index in range(1, 31)]
        table.initialize([
            {"hfpd_id": hfpd_id, "subtask_id": "worker"}
            for hfpd_id in reversed(ids)
        ])
        arguments = [
            (
                str(self.status_path),
                hfpd_id,
                str(self.root / f"{hfpd_id}.out"),
            )
            for hfpd_id in ids
        ]
        with ProcessPoolExecutor(max_workers=8) as executor:
            list(executor.map(concurrent_update, arguments))
        rows = self.rows()
        self.assertEqual([row["hfpd_id"] for row in rows], ids)
        self.assertTrue(all(row["status"] == "completed" for row in rows))
        self.assertEqual(rows[-1]["metric"], "60")


if __name__ == "__main__":
    unittest.main()
