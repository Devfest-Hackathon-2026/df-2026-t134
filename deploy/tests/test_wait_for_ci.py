import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "wait_for_ci", Path(__file__).parents[1] / "wait-for-ci.py"
)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def run(status="completed", conclusion="success", **kwargs):
    return dict(
        head_sha="current",
        head_branch="main",
        event="push",
        run_number=1,
        status=status,
        conclusion=conclusion,
        html_url="https://github.com/example/actions/runs/1",
        **kwargs,
    )


class CiGateTest(unittest.TestCase):
    def state(self, runs):
        return module.ci_state(runs, "current")[0]

    def test_no_run_waits(self):
        self.assertEqual(self.state([]), "waiting")

    def test_pending_run_waits(self):
        for status in ["queued", "in_progress", "waiting", "requested"]:
            self.assertEqual(self.state([run(status=status, conclusion=None)]), "waiting")

    def test_success_allows_deploy(self):
        self.assertEqual(self.state([run()]), "success")

    def test_unsuccessful_ci_blocks_deploy(self):
        for conclusion in ["failure", "cancelled", "timed_out", "skipped", None]:
            self.assertEqual(self.state([run(conclusion=conclusion)]), "failed")

    def test_other_commits_branches_or_events_cannot_authorize_deploy(self):
        for key, value in [
            ("head_sha", "old"),
            ("head_branch", "feature/test"),
            ("event", "pull_request"),
        ]:
            other = run()
            other[key] = value
            self.assertEqual(self.state([other]), "waiting")

    def test_newer_failed_run_overrides_old_success(self):
        newer = run(conclusion="failure")
        newer["run_number"] = 2
        self.assertEqual(self.state([run(), newer]), "failed")
