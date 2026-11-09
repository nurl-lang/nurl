#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Controls for tools/check_pinned_downloads.py.

Each case is a workflow's text with one `run:` block. The checker must
refuse a script piped into a shell on the same line, and on the line after
a `\\` continuation (Agora #535: formal.yml's elan install had that shape
and passed); a download of a tool without `sha256sum -c`; and a curl fetch
of a tool without -f or --retry. It must accept a pinned, checked download,
and a block whose only pipe is in a comment that explains why it is gone.
"""
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_pinned_downloads as cpd  # noqa: E402


def workflow(run):
    body = "\n".join("          " + line for line in run.strip("\n").splitlines())
    return "jobs:\n  j:\n    steps:\n      - name: step\n        run: |\n" + body + "\n"


def whys(run):
    return [why for _, why, _ in cpd.check_text(workflow(run))]


PIPE = "pipes a downloaded script straight into a shell"


class PinnedDownloads(unittest.TestCase):
    def test_pipe_on_one_line_is_refused(self):
        self.assertEqual(whys("curl -sSfL https://example.com/init.sh | sh -s -- -y"), [PIPE])

    def test_pipe_after_a_continuation_is_refused(self):
        run = ("curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh \\\n"
               "  | sh -s -- -y --default-toolchain none")
        self.assertEqual(whys(run), [PIPE])

    def test_pipe_after_two_continuations_is_refused(self):
        run = "wget -qO- \\\n  https://example.com/install.sh \\\n  | sudo bash"
        self.assertEqual(whys(run), [PIPE])

    def test_a_pipe_named_in_a_comment_is_prose(self):
        run = ("# no longer `curl … | sh`: the archive is pinned below\n"
               "curl -fsSL --retry 5 -o /tmp/t.tar.zst https://github.com/o/r/releases/download/v1/t.tar.zst\n"
               "echo \"abc  /tmp/t.tar.zst\" | sha256sum -c -")
        self.assertEqual(whys(run), [])

    def test_a_checked_download_passes(self):
        run = ("curl -fsSL --retry 5 --retry-delay 5 -o /tmp/lean.tar.zst \\\n"
               "  \"https://github.com/leanprover/lean4/releases/download/v4.35.0/lean-4.35.0-linux.tar.zst\"\n"
               "echo \"7289597a  /tmp/lean.tar.zst\" | sha256sum -c -")
        self.assertEqual(whys(run), [])

    def test_an_unchecked_download_is_refused(self):
        run = "curl -fsSL --retry 5 -o /tmp/t.tar.zst https://github.com/o/r/releases/download/v1/t.tar.zst"
        self.assertEqual(whys(run), ["downloads a tool with no checksum check"])

    def test_a_fetch_without_retry_is_refused(self):
        run = ("curl -fsSL -o /tmp/t.tar.gz https://github.com/o/r/releases/download/v1/t.tar.gz\n"
               "echo \"abc  /tmp/t.tar.gz\" | sha256sum -c -")
        self.assertEqual(whys(run), ["fetches a tool with curl but no --retry"])

    def test_the_repository_workflows_pass(self):
        self.assertEqual(cpd.main(), 0)


if __name__ == "__main__":
    unittest.main()
