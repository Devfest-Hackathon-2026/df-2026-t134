"""Wait for the push CI of the exact main commit before requesting cloud credentials."""

import json
import os
import subprocess
import sys
import time


def ci_state(runs, sha):
    matches = [
        run
        for run in runs
        if run["head_sha"] == sha and run["head_branch"] == "main" and run["event"] == "push"
    ]
    if not matches:
        return "waiting", "CI has not started yet"
    latest = max(matches, key=lambda run: run["run_number"])
    if latest["status"] != "completed":
        return "waiting", f"CI is {latest['status']}: {latest['html_url']}"
    if latest["conclusion"] == "success":
        return "success", f"CI passed: {latest['html_url']}"
    return "failed", f"CI concluded {latest['conclusion']}: {latest['html_url']}"


def main():
    repository = os.environ["GITHUB_REPOSITORY"]
    sha = os.environ["GITHUB_SHA"]
    endpoint = (
        f"repos/{repository}/actions/workflows/ci.yml/runs?head_sha={sha}&event=push&per_page=100"
    )
    deadline = time.monotonic() + 20 * 60
    while True:
        response = subprocess.run(
            ["gh", "api", endpoint],
            check=True,
            capture_output=True,
            text=True,
        )
        state, message = ci_state(json.loads(response.stdout)["workflow_runs"], sha)
        print(message, flush=True)
        if state == "success":
            return 0
        if state == "failed":
            print("::error::CI failed. Deployment has not started.", file=sys.stderr)
            return 1
        if time.monotonic() >= deadline:
            print(
                "::error::Timed out waiting 20 minutes for CI. Deployment has not started.",
                file=sys.stderr,
            )
            return 1
        time.sleep(15)


if __name__ == "__main__":
    sys.exit(main())
