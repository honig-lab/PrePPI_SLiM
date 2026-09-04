"""Concurrency-safe, human-readable status tables for PrePPI-SLiM steps."""

from __future__ import annotations

import csv
import fcntl
import glob
import json
import os
from pathlib import Path
import socket
import tempfile
from datetime import datetime


BASE_FIELDS = [
    "hfpd_id",
    "subtask_id",
    "status",
    "health",
    "attempt",
    "queued_at",
    "started_at",
    "finished_at",
    "elapsed_seconds",
    "worker_id",
    "slurm_job_id",
    "work_directory",
    "expected_outputs",
    "outputs_complete",
    "output_count",
    "outputs_present",
    "missing_outputs",
    "message",
]


def now():
    return datetime.now().isoformat(timespec="seconds")


def json_list(values):
    if not values:
        return "[]"
    if isinstance(values, str):
        values = [item for item in values.split(",") if item]
    return json.dumps([str(value) for value in values], separators=(",", ":"))


def output_health(patterns):
    """Return deterministic output presence information for paths or globs."""
    if isinstance(patterns, (str, Path)):
        patterns = [patterns]
    patterns = [str(pattern) for pattern in (patterns or [])]
    present = []
    missing = []
    for pattern in patterns:
        matches = sorted(glob.glob(pattern)) if glob.has_magic(pattern) else []
        if not matches and os.path.exists(pattern):
            matches = [pattern]
        if matches:
            present.extend(matches)
        else:
            missing.append(pattern)
    return {
        "expected_outputs": json_list(patterns),
        "outputs_complete": "yes" if not missing else "no",
        "output_count": len(present),
        "outputs_present": json_list(present),
        "missing_outputs": json_list(missing),
        "health": "healthy" if not missing else "missing_output",
    }


class StatusTable:
    """A CSV table updated under an advisory lock and atomic replacement."""

    def __init__(self, path, extra_fields=()):
        self.path = Path(path)
        self.lock_path = self.path.with_name(self.path.name + ".lock")
        self.fields = list(dict.fromkeys([*BASE_FIELDS, *extra_fields]))

    @staticmethod
    def _key(row):
        return row.get("hfpd_id", ""), row.get("subtask_id", "")

    def _read(self):
        if not self.path.is_file() or self.path.stat().st_size == 0:
            return {}
        with self.path.open(newline="", encoding="utf-8-sig") as handle:
            reader = csv.DictReader(handle)
            return {
                self._key(row): {
                    field: row.get(field, "") for field in self.fields
                }
                for row in reader
                if row.get("hfpd_id")
            }

    def _write(self, rows):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            mode="w",
            newline="",
            encoding="utf-8",
            prefix=f".{self.path.stem}.",
            suffix=".tmp",
            dir=self.path.parent,
            delete=False,
        ) as handle:
            temporary = Path(handle.name)
            writer = csv.DictWriter(
                handle,
                fieldnames=self.fields,
                lineterminator="\n",
                extrasaction="ignore",
            )
            writer.writeheader()
            for key in sorted(rows, key=lambda item: (item[0].casefold(), item[1])):
                writer.writerow(rows[key])
            handle.flush()
            os.fsync(handle.fileno())
        try:
            temporary.chmod(0o664)
            os.replace(temporary, self.path)
        finally:
            temporary.unlink(missing_ok=True)

    def update(self, hfpd_id, subtask_id="", **values):
        unknown = set(values) - set(self.fields)
        if unknown:
            raise ValueError(f"Unknown status columns: {sorted(unknown)}")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.lock_path.open("a+b") as lock_handle:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
            rows = self._read()
            key = str(hfpd_id), str(subtask_id)
            row = rows.get(key, {field: "" for field in self.fields})
            row["hfpd_id"], row["subtask_id"] = key
            for field, value in values.items():
                row[field] = "" if value is None else str(value)
            rows[key] = row
            self._write(rows)
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        self.path.chmod(0o664)
        self.lock_path.chmod(0o664)

    def initialize(self, rows, replace=False):
        """Insert pending rows without discarding valid completed history."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with self.lock_path.open("a+b") as lock_handle:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
            existing = {} if replace else self._read()
            for supplied in rows:
                supplied = dict(supplied)
                key = (
                    str(supplied.pop("hfpd_id")),
                    str(supplied.pop("subtask_id", "")),
                )
                if key in existing and not replace:
                    old = existing[key]
                    if old.get("status") not in {"completed", "skipped"}:
                        continue
                    if supplied.get("status") in {"completed", "skipped"}:
                        old.update({
                            field: str(value)
                            for field, value in supplied.items()
                        })
                        continue
                    attempt = old.get("attempt", "")
                    row = {field: "" for field in self.fields}
                    row["hfpd_id"], row["subtask_id"] = key
                    row["attempt"] = attempt
                    row.update({
                        field: str(value) for field, value in supplied.items()
                    })
                    existing[key] = row
                    continue
                row = {field: "" for field in self.fields}
                row["hfpd_id"], row["subtask_id"] = key
                row.update({
                    field: str(value) for field, value in supplied.items()
                })
                row["status"] = row["status"] or "pending"
                row["health"] = row["health"] or "pending"
                existing[key] = row
            self._write(existing)
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_UN)
        self.path.chmod(0o664)
        self.lock_path.chmod(0o664)

    def start(self, hfpd_id, subtask_id="", expected_outputs=()):
        current = self.get(hfpd_id, subtask_id)
        values = {
            "status": "running",
            "health": "running",
            "attempt": int(current.get("attempt") or 0) + 1,
            "started_at": now(),
            "finished_at": "",
            "elapsed_seconds": "",
            "worker_id": f"{socket.gethostname()}:{os.getpid()}",
            "slurm_job_id": os.environ.get("SLURM_JOB_ID", ""),
            "message": "",
        }
        if expected_outputs:
            values["expected_outputs"] = json_list(expected_outputs)
        self.update(hfpd_id, subtask_id, **values)

    def finish(
        self, hfpd_id, subtask_id="", *, elapsed_seconds=None,
        expected_outputs=(), message="", **values,
    ):
        health = output_health(expected_outputs)
        updates = {
            "status": (
                "completed" if health["health"] == "healthy" else "failed"
            ),
            "finished_at": now(),
            "message": message,
            **health,
            **values,
        }
        if elapsed_seconds is not None:
            updates["elapsed_seconds"] = f"{float(elapsed_seconds):.3f}"
        self.update(hfpd_id, subtask_id, **updates)

    def ready_for_postprocess(
        self, hfpd_id, subtask_id="", *, elapsed_seconds=None,
        expected_outputs=(), message="", **values,
    ):
        health = output_health(expected_outputs)
        updates = {
            "status": "awaiting_postprocess",
            "message": message,
            **health,
            **values,
        }
        if elapsed_seconds is not None:
            updates["elapsed_seconds"] = f"{float(elapsed_seconds):.3f}"
        self.update(hfpd_id, subtask_id, **updates)

    def skip(self, hfpd_id, subtask_id="", message=""):
        self.update(
            hfpd_id,
            subtask_id,
            status="skipped",
            health="not_applicable",
            finished_at=now(),
            expected_outputs="[]",
            outputs_complete="not_applicable",
            output_count=0,
            outputs_present="[]",
            missing_outputs="[]",
            message=message,
        )

    def fail(
        self, hfpd_id, subtask_id="", *, elapsed_seconds=None,
        expected_outputs=(), error="",
    ):
        health = output_health(expected_outputs)
        self.update(
            hfpd_id,
            subtask_id,
            status="failed",
            health="failed",
            finished_at=now(),
            elapsed_seconds=(
                f"{float(elapsed_seconds):.3f}"
                if elapsed_seconds is not None else ""
            ),
            message=str(error).replace("\n", " ").replace("\r", " "),
            **{key: value for key, value in health.items() if key != "health"},
        )

    def get(self, hfpd_id, subtask_id=""):
        return self._read().get((str(hfpd_id), str(subtask_id)), {})

    def rows(self):
        rows = self._read()
        return [
            rows[key]
            for key in sorted(rows, key=lambda item: (item[0].casefold(), item[1]))
        ]

    def all_terminal_and_healthy(
        self, allowed_statuses=("completed", "skipped"),
    ):
        rows = self.rows()
        allowed = set(allowed_statuses)
        return bool(rows) and all(
            row.get("status") in allowed
            and row.get("health") in {"healthy", "not_applicable"}
            and row.get("outputs_complete") in {"yes", "not_applicable"}
            for row in rows
        )

    def remove_lock(self):
        self.lock_path.unlink(missing_ok=True)


def step_status_path(genome_home, step_name):
    return Path(genome_home) / "Pipeline" / f"{step_name}.pip" / "status.csv"
