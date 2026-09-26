"""Offline policy regressions; never dispatch Actions or read credentials."""
import copy
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

import verify_windows_ci_resume as gate

ROOT = Path(__file__).resolve().parent.parent
GUARD = " && steps.resume.outputs.reuse_completed != 'true'"


def original_workflow(current):
    for block in gate.ADDED_STEPS.values():
        current = current.replace(block.strip(), "")
    return (current.replace(GUARD, "")
            .replace("        if: steps.resume.outputs.reuse_completed != 'true'\n", "")
            .replace(gate.WAVE_COMMAND + " " + gate.MIX_PROBE, gate.WAVE_COMMAND)
            .replace(gate.MIX_ENV + "\n", "")
            .replace(gate.INPUTS, "").replace("  actions: read\n", ""))


def evidence():
    run = {
        "id": 123, "run_attempt": 1, "head_sha": "a" * 40,
        "repository": {"full_name": "DanRuguo/dan_player"},
        "head_repository": {"full_name": "DanRuguo/dan_player"},
        "event": "workflow_dispatch", "path": gate.WORKFLOW,
        "status": "completed", "conclusion": "failure", "head_branch": "main",
    }
    job = {"id": 456, "name": gate.JOB, "run_id": 123, "head_sha": "a" * 40,
           "status": "completed", "conclusion": "failure", "steps": []}
    for name in gate.REUSED + gate.PREPARATION + gate.REMAINING:
        conclusion = ("failure" if name == gate.REMAINING[0] else
                      "skipped" if name in gate.REMAINING[1:] else "success")
        job["steps"].append({"name": name, "status": "completed", "conclusion": conclusion})
    return run, [job]


class ResumePolicyTest(unittest.TestCase):
    def assertRejected(self, run=None, jobs=None):
        default_run, default_jobs = evidence()
        with self.assertRaises(ValueError):
            gate.validate_evidence(run or default_run, jobs if jobs is not None else default_jobs,
                                   "DanRuguo/dan_player", "main", 123, 789)

    def test_complete_original_failure_has_exact_successful_categories(self):
        run, jobs = evidence()
        self.assertEqual(gate.validate_evidence(run, jobs, "DanRuguo/dan_player", "main", 123, 789)["id"], 456)

    def test_other_repository_or_fork_is_not_evidence(self):
        for field in ("repository", "head_repository"):
            run, _ = evidence()
            run[field] = {"full_name": "other/dan_player"}
            self.assertRejected(run=run)

    def test_run_identity_workflow_branch_event_and_attempt_must_match(self):
        cases = {"id": 124, "path": ".github/workflows/other.yml",
                 "event": "pull_request", "head_branch": "other", "head_sha": "HEAD",
                 "run_attempt": 0}
        for key, value in cases.items():
            with self.subTest(key=key):
                run, _ = evidence()
                run[key] = value
                self.assertRejected(run=run)

    def test_active_cancelled_skipped_partial_and_successful_runs_are_rejected(self):
        for status, conclusion in (("in_progress", None), ("completed", "cancelled"),
                                   ("completed", "skipped"), ("completed", "success")):
            run, _ = evidence()
            run.update(status=status, conclusion=conclusion)
            self.assertRejected(run=run)

    def test_self_run_or_missing_attempt_cannot_supply_evidence(self):
        run, jobs = evidence()
        with self.assertRaises(ValueError):
            gate.validate_evidence(run, jobs, "DanRuguo/dan_player", "main", 123, 123)
        run.pop("run_attempt")
        self.assertRejected(run=run)

    def test_any_non_successful_reused_category_is_rejected(self):
        for name in gate.REUSED + gate.PREPARATION:
            for conclusion in ("failure", "cancelled", "skipped", None):
                _, jobs = evidence()
                next(s for s in jobs[0]["steps"] if s["name"] == name)["conclusion"] = conclusion
                with self.subTest(category=name, conclusion=conclusion):
                    self.assertRejected(jobs=jobs)

    def test_success_label_without_completed_status_is_rejected(self):
        _, jobs = evidence()
        jobs[0]["steps"][0]["status"] = "in_progress"
        self.assertRejected(jobs=jobs)

    def test_jobs_cannot_be_merged_across_attempts_or_commits(self):
        _, jobs = evidence()
        self.assertRejected(jobs=jobs + copy.deepcopy(jobs))
        self.assertRejected(jobs=[])
        for key, value in (("run_id", 999), ("head_sha", "b" * 40), ("name", "other")):
            _, jobs = evidence()
            jobs[0][key] = value
            self.assertRejected(jobs=jobs)

    def test_missing_or_duplicate_step_rejects_ambiguous_coverage(self):
        _, jobs = evidence()
        jobs[0]["steps"].pop(0)
        self.assertRejected(jobs=jobs)
        _, jobs = evidence()
        jobs[0]["steps"].append(copy.deepcopy(jobs[0]["steps"][0]))
        self.assertRejected(jobs=jobs)

    def test_only_download_failure_and_unexecuted_later_steps_are_supported(self):
        for name, value in ((gate.REMAINING[0], "success"),
                            (gate.REMAINING[1], "failure"), (gate.REMAINING[2], "cancelled")):
            _, jobs = evidence()
            next(s for s in jobs[0]["steps"] if s["name"] == name)["conclusion"] = value
            self.assertRejected(jobs=jobs)

    def test_unrelated_failure_is_not_hidden(self):
        for conclusion in ("failure", "action_required", "stale", None):
            _, jobs = evidence()
            jobs[0]["steps"].append({"name": "new failure", "conclusion": conclusion})
            self.assertRejected(jobs=jobs)

    def test_exact_ci_allowlist_blocks_business_tests_dependencies_and_renames(self):
        gate.validate_diff([["M", p] for p in gate.ALLOW_FILES])
        for file in ("lib/main.dart", "test/playback_statistics_test.dart", "pubspec.lock",
                     "rust/Cargo.lock", "scripts/prepare_windows_dependencies.ps1",
                     "scripts/prepare_bass_fx_runtime.ps1"):
            with self.assertRaises(ValueError, msg=file):
                gate.validate_diff([["M", file]])
        for status in ("D", "R100", "T"):
            with self.assertRaises(ValueError):
                gate.validate_diff([[status, gate.BASS]])

    def test_workflow_preserves_complete_checks_and_mandatory_remaining_categories(self):
        current = (ROOT / gate.WORKFLOW).read_text(encoding="utf-8-sig")
        previous = original_workflow(current)
        self.assertIn("Analyze and test Dan Player", gate.validate_workflows(previous, current))
        for fragment, replacement in (("runs-on: windows-2022", "runs-on: windows-latest"),
                                      ("flutter-version: '3.47.1'", "flutter-version: '3.48.0'"),
                                      ("--locked", ""),
                                      ("-Integration -OutputPath", "-OutputPath"),
                                      ("rustup run stable rustc --version", "rustup update stable")):
            with self.subTest(fragment=fragment), self.assertRaises(ValueError):
                gate.validate_workflows(previous, current.replace(fragment, replacement))

    def test_unverified_boolean_or_bypassed_mandatory_test_is_rejected(self):
        current = (ROOT / gate.WORKFLOW).read_text(encoding="utf-8-sig")
        previous = original_workflow(current)
        for name in gate.REUSED + gate.REMAINING + ("Build Dan Player release",):
            blocks = gate.workflow_steps(current)
            altered = re.sub(r"^        if: .+$", "        if: false", blocks[name], flags=re.M)
            with self.subTest(name=name), self.assertRaises(ValueError):
                gate.validate_workflows(previous, current.replace(blocks[name], altered))

    def test_new_runtime_regression_cannot_be_removed_or_made_nonfatal(self):
        current = (ROOT / gate.WORKFLOW).read_text(encoding="utf-8-sig")
        previous = original_workflow(current)
        blocks = gate.workflow_steps(current)
        for altered in (blocks[gate.REMAINING[1]].replace(" " + gate.MIX_PROBE, ""),
                        blocks[gate.REMAINING[1]].replace("if ($LASTEXITCODE -ne 0) { throw", "# ignored")):
            with self.assertRaises(ValueError):
                gate.validate_workflows(previous, current.replace(blocks[gate.REMAINING[1]], altered))

    def test_flutter_setup_condition_cannot_be_skipped(self):
        current = (ROOT / gate.WORKFLOW).read_text(encoding="utf-8-sig")
        previous = original_workflow(current)
        block = gate.workflow_steps(current)["Set up Flutter 3.47.1"]
        changed = re.sub(r"^        if: .+$", "        if: false", block, flags=re.M)
        with self.assertRaises(ValueError):
            gate.validate_workflows(previous, current.replace(block, changed))

    def test_checkout_action_or_credentials_cannot_change(self):
        current = (ROOT / gate.WORKFLOW).read_text(encoding="utf-8-sig")
        previous = original_workflow(current)
        for original, replacement in (("11d5960a326750d5838078e36cf38b85af677262", "a" * 40),
                                      ("persist-credentials: false", "persist-credentials: true")):
            with self.assertRaises(ValueError):
                gate.validate_workflows(previous, current.replace(original, replacement))

    def test_top_level_environment_and_default_manual_scope_cannot_change(self):
        current = (ROOT / gate.WORKFLOW).read_text(encoding="utf-8-sig")
        previous = original_workflow(current)
        for changed in (current.replace("jobs:\n", "env:\n  MALICIOUS: value\n\njobs:\n"),
                        current.replace("default: integration", "default: bass-packaging"),
                        current.replace("  workflow_dispatch:", "  push:\n  workflow_dispatch:")):
            with self.assertRaises(ValueError):
                gate.validate_workflows(previous, changed)

    def test_added_impact_rewrite_or_modified_evidence_step_is_rejected(self):
        current = (ROOT / gate.WORKFLOW).read_text(encoding="utf-8-sig")
        previous = original_workflow(current)
        malicious = "      - name: Rewrite impact\n        run: |\n          Set-Content tool/ci-impact.json '{\"Profile\":\"documents\"}'\n\n"
        for changed in (current.replace("      - name: Analyze and test Dan Player", malicious + "      - name: Analyze and test Dan Player"),
                        current.replace("if ($LASTEXITCODE -ne 0) { throw 'CI continuation evidence was rejected.' }", "Write-Host accepted")):
            with self.assertRaises(ValueError):
                gate.validate_workflows(previous, changed)

    def test_pin_data_may_change_but_not_https_signature_pe_or_hash_verification(self):
        script = (ROOT / gate.BASS).read_text(encoding="utf-8-sig")
        old = script.replace("Version = '2.4.13'", "Version = '2.4.12'")
        gate.validate_bass_changes(old, script)
        for old_value, new_value in (("https://www.un4seen.com/files/bass24.zip", "https://evil.invalid/bass.zip"),
                                     ("Expected an AMD64", "Other architecture"),
                                     ("$actualHash -ne $ExpectedHash", "$false"),
                                     ("$packages = @(", "$packages = $(")):
            with self.assertRaises(ValueError, msg=old_value):
                gate.validate_bass_changes(script, script.replace(old_value, new_value))

    def test_pin_block_is_constant_only_and_all_original_nine_packages_remain(self):
        script = (ROOT / gate.BASS).read_text(encoding="utf-8-sig")
        for before, after in (("Name = 'BASS'", "Name = 'OTHER'"),
                              ("ArchiveSize = 957484", "ArchiveSize = $(1)"),
                              ("Notice = 'bass.txt'", "Notice = '../other.txt'"),
                              ("#requires -Version 5.1", "#requires -Version 1.0"),
                              ("#requires -Version 5.1", "#Requires -Version 1.0")):
            with self.assertRaises(ValueError, msg=before):
                gate.validate_bass_changes(script, script.replace(before, after))

    def test_default_integration_requires_no_api_and_never_sets_reuse_true(self):
        with tempfile.TemporaryDirectory() as temp:
            files = {name: str(Path(temp) / name) for name in ("GITHUB_OUTPUT", "GITHUB_STEP_SUMMARY")}
            output = str(Path(temp) / "receipt.json")
            with patch.dict(os.environ, files), patch("sys.argv", ["gate", "--output", output]), \
                    patch.object(gate, "read_api", side_effect=AssertionError("Default must not fetch evidence")):
                gate.main()
            self.assertIn("reuse_completed=false", Path(files["GITHUB_OUTPUT"]).read_text())

    def test_full_scope_rejects_stray_prior_id_and_resume_rejects_absent_id(self):
        for arguments in (("--scope", "integration", "--prior-run-id", "123"),
                          ("--scope", "bass-packaging"),
                          ("--scope", "bass-packaging", "--prior-run-id", "../123")):
            with patch("sys.argv", ["gate", "--output", "unused", *arguments]), self.assertRaises(ValueError):
                gate.main()

    def test_cli_queries_exact_attempt_and_emits_auditable_receipt_only_after_all_checks(self):
        run, jobs = evidence()
        run["html_url"] = "https://github.com/DanRuguo/dan_player/actions/runs/123"
        workflow = (ROOT / gate.WORKFLOW).read_text(encoding="utf-8-sig")
        bass = (ROOT / gate.BASS).read_text(encoding="utf-8-sig").strip()
        def fake_git(_, *args):
            if args[0] == "show":
                return bass if args[1].endswith(gate.BASS) else original_workflow(workflow).strip()
            return {"rev-parse": "b" * 40, "status": "", "diff": "M\t" + gate.BASS}[args[0]]
        with tempfile.TemporaryDirectory() as temp:
            env = {"GITHUB_OUTPUT": str(Path(temp) / "output"),
                   "GITHUB_STEP_SUMMARY": str(Path(temp) / "summary"),
                   "GITHUB_SHA": "b" * 40, "GITHUB_REF_NAME": "main",
                   "GITHUB_REPOSITORY": "DanRuguo/dan_player", "GITHUB_RUN_ID": "789"}
            target = str(Path(temp) / "evidence.json")
            with patch.dict(os.environ, env), patch("sys.argv", ["gate", "--scope", "bass-packaging",
                        "--prior-run-id", "123", "--output", target]), \
                    patch.object(gate, "read_api", side_effect=[run, {"total_count": 1, "jobs": jobs}]) as api, \
                    patch.object(gate, "git", side_effect=fake_git), patch.object(gate.subprocess, "run") as ancestry:
                gate.main()
            self.assertEqual(api.call_args_list[1].args[1], "actions/runs/123/attempts/1/jobs?per_page=100")
            self.assertIn("--is-ancestor", ancestry.call_args.args[0])
            actual = json.loads(Path(target).read_text())
            self.assertTrue(actual["reuseCompleted"])
            self.assertEqual(actual["priorJob"]["id"], 456)
            self.assertEqual(actual["currentSha"], "b" * 40)
            self.assertEqual(actual["additionalReviewedRuntimeProbe"], gate.MIX_PROBE)
            self.assertIn("reuse_completed=true", Path(env["GITHUB_OUTPUT"]).read_text())

    def test_dirty_or_wrong_checkout_never_fetches_evidence_or_sets_reuse(self):
        for sha, dirty in (("b" * 40, "M lib/main.dart"), ("c" * 40, "")):
            with tempfile.TemporaryDirectory() as temp:
                target = str(Path(temp) / "evidence.json")
                env = {"GITHUB_REPOSITORY": "DanRuguo/dan_player", "GITHUB_SHA": "b" * 40}
                with patch.dict(os.environ, env), patch("sys.argv", ["gate", "--scope", "bass-packaging",
                        "--prior-run-id", "123", "--output", target]), \
                        patch.object(gate, "git", side_effect=[sha, dirty]), \
                        patch.object(gate, "read_api") as api, self.assertRaises(ValueError):
                    gate.main()
                api.assert_not_called()
                self.assertFalse(Path(target).exists())


if __name__ == "__main__":
    unittest.main()
