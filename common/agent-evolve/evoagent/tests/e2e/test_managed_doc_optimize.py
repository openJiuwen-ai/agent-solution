"""Live Adapter E2E for AgentRule managed-document optimization."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

pytestmark = [
    pytest.mark.managed_doc_e2e,
    pytest.mark.skipif(
        os.environ.get("EVO_RUN_MANAGED_DOC_E2E") != "1",
        reason="set EVO_RUN_MANAGED_DOC_E2E=1 to run the live Adapter E2E",
    ),
]


def test_agent_rule_optimization_changes_live_agent_behavior(tmp_path: Path) -> None:
    """A real managed-doc apply restarts the agent and changes its next answer."""
    from tests.e2e.support.harness import ManagedDocE2EHarness

    with ManagedDocE2EHarness(tmp_path) as harness:
        assert harness.ask("Which rule version is active?") == "OLD"

        report = harness.optimize()

        snapshot = harness.get_managed_doc()
        task = harness.get_task(report.managed_doc_task_ids[-1])
        assert task["status"] == "SUCCEEDED"
        assert task["down_seen"] is True
        assert snapshot["pending_apply"] is False
        assert snapshot["file_revision"] == snapshot["applied_revision"]
        assert harness.ask("Which rule version is active now?") == "NEW"

        assert report.managed_doc_kind == "agent_rule"
        assert report.epochs_completed == 1
        assert report.edits_applied == 1
        assert "candidate" in report.gate_results
        assert "ANSWER=OLD" in (report.managed_doc_content_before or "")
        assert "ANSWER=NEW" in (report.managed_doc_content_after or "")
        assert (report.artifact_dir / "managed_doc_final.md").read_text(
            encoding="utf-8"
        ) == report.managed_doc_content_after
        diff = (report.artifact_dir / "managed_doc_diff.patch").read_text(encoding="utf-8")
        assert "-ANSWER=OLD" in diff
        assert "+ANSWER=NEW" in diff
