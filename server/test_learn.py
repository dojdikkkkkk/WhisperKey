import subprocess
import unittest
from unittest.mock import patch

import learn


class PiBackendTests(unittest.TestCase):
    def test_is_registered_as_a_learning_backend(self):
        self.assertIs(learn.BACKENDS["pi"], learn.backend_pi)

    @patch.object(learn.subprocess, "run")
    @patch.object(learn, "find_cli", return_value="/usr/local/bin/pi")
    def test_runs_pi_in_constrained_print_mode(self, find_cli, run):
        run.return_value = subprocess.CompletedProcess([], 0, stdout='{"new_terms": []}', stderr="")

        output = learn.backend_pi("learning prompt", {})

        self.assertEqual(output, '{"new_terms": []}')
        find_cli.assert_called_once_with(
            "pi", (learn.os.path.expanduser("~/.npm-global/bin/pi"),)
        )
        run.assert_called_once_with(
            [
                "/usr/local/bin/pi",
                "-p",
                "--no-session",
                "--no-tools",
                "learning prompt",
            ],
            capture_output=True,
            text=True,
            timeout=240,
        )

    @patch.object(learn, "find_cli", return_value=None)
    def test_reports_when_pi_is_missing(self, _find_cli):
        with self.assertRaisesRegex(RuntimeError, "pi CLI not found"):
            learn.backend_pi("learning prompt", {})

    @patch.object(learn.subprocess, "run")
    @patch.object(learn, "find_cli", return_value="/usr/local/bin/pi")
    def test_reports_pi_failure(self, _find_cli, run):
        run.return_value = subprocess.CompletedProcess([], 1, stdout="", stderr="authentication failed")

        with self.assertRaisesRegex(RuntimeError, "pi failed: authentication failed"):
            learn.backend_pi("learning prompt", {})


if __name__ == "__main__":
    unittest.main()
