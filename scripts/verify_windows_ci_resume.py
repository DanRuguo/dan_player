"""Fail-closed evidence gate for the single supported Windows CI continuation."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.request

WORKFLOW = ".github/workflows/windows_ci.yml"
JOB = "Test and package Windows x64"
BASS = "scripts/prepare_bass_runtime.ps1"
ALLOW_FILES = {
    WORKFLOW, BASS, "scripts/verify_windows_ci_resume.py",
    "scripts/test_windows_ci_resume.py", "scripts/native_tests/bassmix_persistent_test.dart",
}
REUSED = (
    "Verify version and validation policy",
    "Test native installer transactions and update handoff",
    "Analyze and test Dan Player", "Analyze and test desktop lyrics",
    "Test native backdrop and desktop integration policies",
    "Build desktop lyric test harness", "Test owned lyric window geometry and focus",
)
PREPARATION = (
    "Select full integration checks",
    "Set up Flutter 3.47.1", "Set up Rust stable (MSVC x64)",
    "Record toolchain and prepare both Flutter projects", "Build Dan Player release",
)
REMAINING = (
    "Download and verify all nine BASS packages",
    "Test real BASS waveform decoding with synthetic audio",
    "Assemble portable ZIP and SHA256SUMS", "Upload portable package",
)
MIX_PROBE = "scripts/native_tests/bassmix_persistent_test.dart"
WAVE_COMMAND = "flutter test --no-pub --concurrency=1 test/waveform_native_test.dart test/waveform_review_native_snapshot2_test.dart"
MIX_ENV = "          $env:DAN_PLAYER_BASS_RUNTIME = Join-Path $env:GITHUB_WORKSPACE 'tool/bass/runtime-x64-9pkg/BASS'"
INPUTS = """    inputs:
      resume_scope:
        description: 'Full integration, or verified continuation after a BASS download failure'
        type: choice
        required: true
        default: integration
        options:
          - integration
          - bass-packaging
      prior_run_id:
        description: 'Completed original Windows CI run ID (required only for bass-packaging)'
        type: string
        required: false
"""
ADDED_STEPS = {
    "Test continuation evidence policy": """      - name: Test continuation evidence policy
        run: |
          python -B -m unittest discover -s scripts -p test_windows_ci_resume.py -v
          if ($LASTEXITCODE -ne 0) { throw 'CI continuation policy tests failed.' }
""",
    "Verify continuation evidence": """      - name: Verify continuation evidence
        id: resume
        env:
          GITHUB_TOKEN: ${{ github.token }}
          RESUME_SCOPE: ${{ inputs.resume_scope }}
          PRIOR_RUN_ID: ${{ inputs.prior_run_id }}
        run: |
          python -B .\\scripts\\verify_windows_ci_resume.py --scope "$env:RESUME_SCOPE" --prior-run-id "$env:PRIOR_RUN_ID" --output tool/ci-resume-evidence.json
          if ($LASTEXITCODE -ne 0) { throw 'CI continuation evidence was rejected.' }
""",
    "Preserve continuation evidence": """      - name: Preserve continuation evidence
        if: always()
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4
        with:
          name: windows-ci-evidence-${{ github.sha }}
          path: tool/ci-resume-evidence.json
          if-no-files-found: ignore
          retention-days: 14
""",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def validate_evidence(run, jobs, repository, branch, prior_id, current_run_id):
    require(run.get("id") == prior_id and prior_id != current_run_id,
            "Prior run ID is missing, mismatched or self-referential")
    require(run.get("repository", {}).get("full_name", "").casefold() == repository.casefold(),
            "Prior run belongs to another repository")
    require(run.get("head_repository", {}).get("full_name", "").casefold() == repository.casefold(),
            "Prior run source belongs to another repository")
    require(run.get("event") == "workflow_dispatch" and run.get("path") == WORKFLOW,
            "Prior run is not the manual Windows CI workflow")
    require(run.get("head_branch") == branch, "Prior run branch differs")
    require(run.get("status") == "completed" and run.get("conclusion") == "failure",
            "Only a completed failed original run may be continued")
    require(re.fullmatch(r"[a-f0-9]{40}", run.get("head_sha", "")), "Invalid prior SHA")
    require(type(run.get("run_attempt")) is int and run["run_attempt"] > 0,
            "Missing exact prior attempt")
    require(len(jobs) == 1 and jobs[0].get("name") == JOB,
            "Expected exactly one complete Windows build job")
    job = jobs[0]
    require(job.get("status") == "completed" and job.get("conclusion") == "failure",
            "Prior Windows job did not finish with a BASS failure")
    require(job.get("head_sha") == run["head_sha"] and job.get("run_id") == prior_id,
            "Job does not belong to the exact prior commit and run")
    steps = job.get("steps", [])
    by_name = {}
    for step in steps:
        require(step["name"] not in by_name, "Ambiguous duplicate prior step")
        by_name[step["name"]] = step
    for name in REUSED + PREPARATION:
        step = by_name.get(name, {})
        require(step.get("status") == "completed" and step.get("conclusion") == "success",
                f"Category did not pass completely: {name}")
    download = by_name.get(REMAINING[0], {})
    require(download.get("status") == "completed" and download.get("conclusion") == "failure",
            "The supported continuation requires an actual BASS download failure")
    for name in REMAINING[1:]:
        step = by_name.get(name, {})
        require(step.get("status") == "completed" and step.get("conclusion") == "skipped",
                f"Later category is not the expected unexecuted step: {name}")
    require(all(step.get("conclusion") in {"success", "skipped"}
                or step.get("name") == REMAINING[0] for step in steps),
            "Another failed category cannot be reused")
    return job


def workflow_steps(text):
    text = text.replace("\r\n", "\n")
    matches = list(re.finditer(r"^      - name: (.+)$", text, re.M))
    require(matches, "Missing expected workflow step structure")
    result = {}
    for index, match in enumerate(matches):
        name = match[1]
        require(name not in result, "Duplicate workflow step")
        result[name] = text[match.start():matches[index + 1].start()
                            if index + 1 < len(matches) else len(text)].strip()
    return result


def without_conditions(block):
    return "\n".join(line for line in block.splitlines()
                     if line.strip() and not line.lstrip().startswith("#") and
                     not line.startswith("        if:")).strip()


def validate_workflows(previous, current):
    previous = previous.replace("\r\n", "\n")
    current = current.replace("\r\n", "\n")
    old, new = workflow_steps(previous), workflow_steps(current)
    original_order = list(old)
    expected_order = original_order[:1] + list(ADDED_STEPS)[:2] + original_order[1:] + list(ADDED_STEPS)[2:]
    require(list(new) == expected_order, "Unexpected added, removed or reordered workflow step")
    for name, expected in ADDED_STEPS.items():
        require(without_conditions(new[name]) == without_conditions(expected) and
                re.findall(r"^        if: (.+)$", new[name], re.M) ==
                re.findall(r"^        if: (.+)$", expected, re.M),
                f"Added evidence step differs from its audited contract: {name}")
    before_steps = previous[:previous.index("      - name: Checkout")]
    current_prefix = current[:current.index("      - name: Checkout")]
    require(current_prefix.count(INPUTS) == 1 and
            current_prefix.count("  actions: read\n") == 1,
            "Only the audited manual inputs and read-only Actions permission may be added")
    current_prefix = current_prefix.replace(INPUTS, "").replace("  actions: read\n", "")
    require(current_prefix == before_steps,
            "Workflow trigger, runner, shell, environment, permissions or concurrency changed")
    # Runner, timeout, project environment and default shell are part of the
    # evidence; changing a toolchain/setup command invalidates every reuse.
    header = re.compile(r"^jobs:\n(.*?)^    steps:", re.M | re.S)
    old_header = header.search(previous.replace("\r\n", "\n"))
    new_header = header.search(current.replace("\r\n", "\n"))
    require(old_header and new_header and old_header[1] == new_header[1],
            "Runner, shell, timeout or job environment changed")
    protected = tuple(old)
    for name in protected:
        current_block = new.get(name, "")
        if name == REMAINING[1]:
            require(WAVE_COMMAND + " " + MIX_PROBE in current_block and
                    MIX_ENV in current_block,
                    "Waveform and reviewed mixer native regressions must both execute")
            current_block = current_block.replace(WAVE_COMMAND + " " + MIX_PROBE, WAVE_COMMAND)
            current_block = current_block.replace(MIX_ENV + "\n", "")
        require(name in old and name in new and
                without_conditions(old[name]) == without_conditions(current_block),
                f"Protected category/toolchain command changed: {name}")
    for name in REUSED:
        original = re.findall(r"^        if: (.+)$", old[name], re.M)
        actual = re.findall(r"^        if: (.+)$", new[name], re.M)
        require(len(original) == (0 if name == "Verify version and validation policy" else 1),
                f"Unexpected original category condition: {name}")
        expected = [(original[0] + " && " if original else "") +
                    "steps.resume.outputs.reuse_completed != 'true'"]
        require(actual == expected,
                f"Reuse condition is not the exact audited gate: {name}")
    for name in (name for name in old if name not in REUSED):
        require(re.findall(r"^        if: (.+)$", new[name], re.M) ==
                re.findall(r"^        if: (.+)$", old[name], re.M),
                f"Required remaining category was made optional: {name}")
    require("-Integration" in old["Select full integration checks"],
            "Original run did not select the complete integration path")
    return {name: hashlib.sha256(without_conditions(old[name]).encode()).hexdigest()
            for name in protected}


def package_constants(script):
    match = re.search(r"^\$packages = @\(\n(.*?)^\)\s*$", script, re.M | re.S)
    require(match, "Missing exact BASS package constant block")
    body = match[1]
    records = []
    record_pattern = r"\s*\[pscustomobject\]@\{\s*(.*?)\s*\}"
    for record in re.finditer(record_pattern, body, re.S):
        values = {}
        fields = list(re.finditer(r"(\w+)\s*=\s*(?:'([^'\n]+)'|(\d+))", record[1]))
        for field in fields:
            require(field[1] not in values, "Duplicate BASS pin field")
            values[field[1]] = field[2] if field[2] is not None else int(field[3])
        residue = re.sub(r"(\w+)\s*=\s*(?:'([^'\n]+)'|(\d+))", "", record[1])
        require(not residue.replace(";", "").strip(), "Executable BASS pin expression")
        require(set(values) == {"Name", "Version", "Archive", "Dll", "Notice", "Url",
                                "ArchiveSize", "ArchiveSha256", "DllSha256"},
                "BASS pin structure changed")
        require(re.fullmatch(r"\d+(?:\.\d+){1,3}", values["Version"]), "Invalid version pin")
        require(values["ArchiveSize"] > 0, "Invalid archive size pin")
        for key in ("ArchiveSha256", "DllSha256"):
            require(re.fullmatch(r"[A-F0-9]{64}", values[key]), "Invalid SHA-256 pin")
        records.append(values)
    require(len(records) == 9 and len({r["Name"] for r in records}) == 9,
            "All nine original BASS packages are required")
    require(not re.sub(record_pattern, "", body, flags=re.S).strip(),
            "Unexpected code in BASS package block")
    remainder = script[:match.start()] + "<package constants>\n" + script[match.end():]
    # Permit audit comments/date only, never #requires or download verification.
    remainder = re.sub(r"^\s*#(?!requires\b)[^\n]*\n", "", remainder, flags=re.M | re.I)
    remainder = re.sub(r"(Pinned official HTTPS archives reviewed through )\d{4}-\d{2}-\d{2}",
                       r"\1<audit-date>", remainder)
    return records, remainder


def validate_bass_changes(previous, current):
    old, old_code = package_constants(previous.replace("\r\n", "\n"))
    new, new_code = package_constants(current.replace("\r\n", "\n"))
    require(old_code == new_code, "BASS download/security code changed outside pin data")
    for before, after in zip(old, new):
        for field in ("Name", "Archive", "Dll", "Notice", "Url"):
            require(before[field] == after[field], f"Official BASS source/identity changed: {field}")
    return [{"package": before["Name"], "previous": before, "current": after}
            for before, after in zip(old, new) if before != after]


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True,
                                   encoding="utf-8").strip()


def validate_diff(changes):
    require(all(status in {"A", "M"} and path in ALLOW_FILES for status, path in changes),
            "Reuse denied: changes include business, tests, dependencies or other CI logic")


def read_api(repository, route):
    request = urllib.request.Request(
        f"https://api.github.com/repos/{repository}/{route}",
        headers={"Accept": "application/vnd.github+json",
                 "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
                 "X-GitHub-Api-Version": "2026-03-10"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", choices=("integration", "bass-packaging"), default="integration")
    parser.add_argument("--prior-run-id", default="")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    receipt = {"schema": 1, "scope": args.scope, "reuseCompleted": False}
    if args.scope == "integration":
        require(not args.prior_run_id, "A prior run cannot accompany full integration")
    else:
        require(re.fullmatch(r"[1-9][0-9]*", args.prior_run_id), "Continuation requires a numeric prior run ID")
        repo = Path(__file__).resolve().parent.parent
        repository = os.environ["GITHUB_REPOSITORY"]
        require(re.fullmatch(r"[\w.-]+/[\w.-]+", repository), "Invalid repository")
        current_sha = os.environ["GITHUB_SHA"]
        require(re.fullmatch(r"[a-f0-9]{40}", current_sha), "Invalid current SHA")
        require(git(repo, "rev-parse", "HEAD") == current_sha and
                not git(repo, "status", "--porcelain"), "Checkout is not the exact clean current commit")
        prior_id = int(args.prior_run_id)
        run = read_api(repository, f"actions/runs/{prior_id}")
        attempt = run.get("run_attempt")
        require(type(attempt) is int and attempt > 0, "Missing prior attempt")
        payload = read_api(repository, f"actions/runs/{prior_id}/attempts/{attempt}/jobs?per_page=100")
        require(payload.get("total_count") == 1, "Prior attempt jobs were incomplete or ambiguous")
        job = validate_evidence(run, payload["jobs"], repository, os.environ["GITHUB_REF_NAME"],
                                prior_id, int(os.environ["GITHUB_RUN_ID"]))
        subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor",
                        run["head_sha"], current_sha], check=True)
        changes = [line.split("\t", 1) for line in
                   git(repo, "diff", "--name-status", "--no-renames", run["head_sha"], current_sha, "--").splitlines()]
        validate_diff(changes)
        old_workflow = git(repo, "show", f"{run['head_sha']}:{WORKFLOW}")
        new_workflow = (repo / WORKFLOW).read_text(encoding="utf-8-sig").strip()
        protected = validate_workflows(old_workflow, new_workflow)
        pins = validate_bass_changes(git(repo, "show", f"{run['head_sha']}:{BASS}"),
                                     (repo / BASS).read_text(encoding="utf-8-sig").strip())
        receipt.update({"reuseCompleted": True, "repository": repository,
                        "priorRun": run, "priorJob": job, "currentSha": current_sha,
                        "changedFiles": changes, "protectedCategorySha256": protected,
                        "bassPinChanges": pins, "reusedCategories": REUSED,
                        "requiredRemainingCategories": REMAINING,
                        "additionalReviewedRuntimeProbe": MIX_PROBE,
                        "preparationRepeated": "Dependencies and main Release build supply fresh packaging artifacts; no full test category is repeated."})
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
        stream.write(f"reuse_completed={str(receipt['reuseCompleted']).lower()}\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
        stream.write(f"## Windows CI scope: {args.scope}\n\n")
        if receipt["reuseCompleted"]:
            stream.write(f"Prior run [{prior_id}]({run['html_url']}) / attempt {attempt} / `{run['head_sha']}`.\n\n")
            stream.write("Reused complete categories:\n\n" + "".join(f"- {name}\n" for name in REUSED))
            stream.write("\nRequired remaining categories:\n\n" + "".join(f"- {name}\n" for name in REMAINING))
            stream.write(f"\nReal native waveform verification also runs `{MIX_PROBE}` for the reviewed runtime upgrade.\n")
            stream.write("\n" + receipt["preparationRepeated"] + "\n")
        else:
            stream.write("Default complete integration; no prior category is skipped.\n")


if __name__ == "__main__":
    main()
