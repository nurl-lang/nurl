#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Controls for tools/check_may_panic.py (agora #537).

- may_panic() finds an exported entry that calls nurl_panic directly, one
  that reaches it through a static helper, and one that longjmps; it skips
  an internal helper and an entry whose only route is a call through a
  pointer;
- main() fails when nurlc answers F for an entry that can panic, and
  passes when it answers T — against a stand-in nurlc, so the gate is
  shown to fire without a compiler that lacks the entry.
"""
import os
import stat
import sys
import tempfile
import unittest
from unittest import mock

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import check_may_panic as cmp  # noqa: E402

IR = """
define void @nurl_direct(ptr %m) {
  call void @nurl_panic(ptr %m)
  ret void
}
define internal void @nurl__helper(ptr %m) {
  call void @nurl_panic(ptr %m)
  ret void
}
define void @nurl_through_helper(ptr %m) {
  %r = call i32 @pthread_mutex_lock(ptr %m)
  call void @nurl__helper(ptr %m)
  ret void
}
define void @nurl_jumps(ptr %j) {
  call void @longjmp(ptr %j, i32 1)
  ret void
}
define void @nurl_indirect(ptr %f) {
  call void %f()
  ret void
}
define void @nurl_plain(i64 %x) {
  %y = add i64 %x, 1
  ret void
}
"""


def fake_nurlc(tmp, answer):
    path = os.path.join(tmp, "nurlc")
    with open(path, "w") as fh:
        fh.write("#!/bin/sh\nfor n in $(echo \"${1#--may-panic=}\" | tr , ' '); do echo \"$n %s\"; done\n" % answer)
    os.chmod(path, os.stat(path).st_mode | stat.S_IEXEC)
    return path


class MayPanic(unittest.TestCase):
    def test_the_call_graph(self):
        found = cmp.may_panic(IR)
        self.assertEqual(sorted(found), ["nurl_direct", "nurl_jumps", "nurl_through_helper"])
        self.assertEqual(found["nurl_through_helper"], ["nurl_through_helper", "nurl__helper", "nurl_panic"])

    def test_an_entry_nurlc_takes_for_safe_fails(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(cmp, "runtime_ir", return_value=IR):
            self.assertEqual(cmp.main(["x", fake_nurlc(tmp, "F")]), 1)

    def test_entries_nurlc_knows_pass(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(cmp, "runtime_ir", return_value=IR):
            self.assertEqual(cmp.main(["x", fake_nurlc(tmp, "T")]), 0)


if __name__ == "__main__":
    unittest.main()
