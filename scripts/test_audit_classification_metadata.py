"""Synthetic audit-error regression tests; never access music or user files."""

import contextlib
import errno
import io
import json
import struct
import unittest
from unittest import mock

import audit_classification_metadata as audit


class AuditFailurePrivacyTest(unittest.TestCase):
    def summarize(self, errors):
        source = mock.Mock(suffix=".mp3")
        source.is_file.return_value = True
        directory = mock.Mock()
        directory.rglob.return_value = [source] * len(errors)
        output = io.StringIO()
        with (
            mock.patch.object(audit.pathlib, "Path", return_value=directory),
            mock.patch.object(audit, "metadata", side_effect=errors),
            mock.patch.object(audit.sys, "argv", ["audit", "synthetic-root"]),
            contextlib.redirect_stdout(output),
        ):
            audit.main()
        self.assertNotIn("PRIVATE_SENTINEL", output.getvalue())
        self.assertNotIn("track.mp3", output.getvalue())
        result = json.loads(output.getvalue())
        self.assertEqual(result["counts"], {"audio_files": len(errors)})
        return result["failures"]

    def test_os_error_retains_only_type_and_numeric_errno(self):
        error = PermissionError(
            errno.EACCES,
            "PRIVATE_SENTINEL message",
            r"R:\PRIVATE_SENTINEL\track.mp3",
        )
        self.assertEqual(
            self.summarize([error]),
            {f"PermissionError (errno={errno.EACCES})": 1},
        )

    def test_errors_without_errno_omit_original_messages(self):
        for error_type in (OSError, ValueError, KeyError, IndexError, struct.error):
            with self.subTest(error_type=error_type.__name__):
                self.assertEqual(
                    self.summarize([error_type("PRIVATE_SENTINEL message")]),
                    {error_type.__name__: 1},
                )

    def test_non_numeric_errno_is_not_echoed(self):
        error = OSError("PRIVATE_SENTINEL errno", "PRIVATE_SENTINEL message")
        self.assertEqual(self.summarize([error]), {"OSError": 1})

    def test_same_failure_kind_aggregates_without_source_identifiers(self):
        errors = [
            PermissionError(errno.EACCES, f"PRIVATE_SENTINEL message {index}")
            for index in range(2)
        ]
        self.assertEqual(
            self.summarize(errors),
            {f"PermissionError (errno={errno.EACCES})": 2},
        )


if __name__ == "__main__":
    unittest.main()
