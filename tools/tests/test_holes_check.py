#!/usr/bin/env python3
"""tools/fuzz/holes/check.sh's verdicts, against a stand-in toolchain.

check.sh is the gate that says no probe is a hole. It must not say so when it
could not tell: a build that failed without a compile error (no
stdlib/runtime.o, a broken linker), a sanitizer build that produced no binary
(no ASan runtime), a run that did not finish. Before Agora #232 the first
counted as REJECTED and the other two as "ran clean", so a box without the
ASan runtime, or a tree without its runtime objects, reported `holes: 0`.

Each control copies the real check.sh (and map.sh, the table of what each
probe's `// map:` line promises) into a scratch tree whose `nurl.sh` is a
stand-in. The probe's first line picks what the stand-in does; its map line
says `rejected` for a `rejected` probe and `runs-clean` for any other, unless
the mode names it (`clean=rejected`). A verdict the map line does not promise
is a MISMATCH (Agora #318).
"""
import os
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CHECK = os.path.join(ROOT, "tools", "fuzz", "holes", "check.sh")
MAP = os.path.join(ROOT, "tools", "fuzz", "holes", "map.sh")

STANDIN = r"""#!/bin/bash
# nurl.sh SRC OUT, as check.sh calls it; the probe's first line decides.
src="$1"; out="$2"
mode=$(head -1 "$src")
case "$mode" in
  "// rejected")
    echo "[1/2] $src -> $out.ll"
    echo "$src:3:5: error: a borrow outlives its owner"
    echo "error: compilation aborted — 1 borrow-checker violation"
    exit 1 ;;
  "// no-runtime")
    echo "ERROR: stdlib/runtime.o not found at /tree/stdlib/runtime.o" >&2
    exit 1 ;;
  "// link")
    echo "/usr/bin/ld: cannot find -lsqlite3: No such file or directory" >&2
    echo "clang: error: linker command failed with exit code 1 (use -v to see invocation)" >&2
    exit 1 ;;
esac
if [ -n "${NURL_SAN:-}" ] && [ "$mode" = "// no-asan" ]; then
  echo "/usr/bin/ld: cannot find libclang_rt.asan-x86_64.a: No such file or directory" >&2
  echo "clang: error: linker command failed with exit code 1 (use -v to see invocation)" >&2
  exit 1
fi
case "$mode" in
  "// hole") body='echo "==1==ERROR: AddressSanitizer: heap-use-after-free on address 0x6020" >&2; exit 1' ;;
  "// slow") body='sleep 20' ;;
  *) body='exit 0' ;;
esac
printf '#!/bin/bash\n%s\n' "$body" > "$out"
chmod +x "$out"
"""


class HolesCheck(unittest.TestCase):
    def setUp(self):
        self.tree = tempfile.mkdtemp(prefix="holes-check-")
        self.dir = os.path.join(self.tree, "tools", "fuzz", "holes")
        os.makedirs(self.dir)
        shutil.copy(CHECK, os.path.join(self.dir, "check.sh"))
        shutil.copy(MAP, os.path.join(self.dir, "map.sh"))
        nurl = os.path.join(self.tree, "nurl.sh")
        with open(nurl, "w") as f:
            f.write(STANDIN)
        os.chmod(nurl, os.stat(nurl).st_mode | stat.S_IXUSR)

    def tearDown(self):
        shutil.rmtree(self.tree)

    def run_check(self, *modes, timeout=None, map_line=True):
        names = []
        for i, spec in enumerate(modes):
            mode, _, want = spec.partition("=")
            want = want or ("rejected" if mode == "rejected" else "runs-clean")
            name = f"p{i}_{mode.replace('-', '_')}.nu"
            ml = f"// map: §0 | A2 | {want} | - | control: {mode}\n" if map_line else ""
            with open(os.path.join(self.dir, name), "w") as f:
                f.write(f"// {mode}\n{ml}@ main → i {{ ^ 0 }}\n")
            names.append(name)
        env = dict(os.environ)
        env.pop("HOLES_TIMEOUT", None)
        if timeout is not None:
            env["HOLES_TIMEOUT"] = str(timeout)
        p = subprocess.run(["bash", os.path.join(self.dir, "check.sh"), *names],
                           capture_output=True, text=True, env=env, timeout=120)
        verdicts = [line.split()[0] for line in p.stdout.splitlines()
                    if line.split() and line.split()[0] in ("REJECTED", "HOLE", "ACCEPTED", "UNCHECKED")]
        return p.returncode, verdicts, p.stdout

    def test_a_compile_error_is_rejected(self):
        rc, v, out = self.run_check("rejected")
        self.assertEqual((rc, v), (0, ["REJECTED"]), out)
        self.assertIn("error: a borrow outlives its owner", out)

    def test_a_clean_run_is_accepted(self):
        rc, v, out = self.run_check("clean")
        self.assertEqual((rc, v), (0, ["ACCEPTED"]), out)

    def test_a_sanitizer_fault_is_a_hole(self):
        rc, v, out = self.run_check("hole")
        self.assertEqual((rc, v), (1, ["HOLE"]), out)
        self.assertIn("heap-use-after-free", out)

    def test_a_build_without_its_runtime_is_no_verdict(self):
        # Was REJECTED: every probe "rejected", holes: 0.
        rc, v, out = self.run_check("no-runtime")
        self.assertEqual((rc, v), (1, ["UNCHECKED"]), out)
        self.assertIn("runtime.o not found", out)

    def test_a_link_failure_is_not_a_rejection(self):
        # `clang: error:` is not the compiler refusing the program.
        rc, v, out = self.run_check("link")
        self.assertEqual((rc, v), (1, ["UNCHECKED"]), out)

    def test_no_asan_runtime_is_no_verdict(self):
        # Was ACCEPTED: the missing sanitizer binary "ran clean".
        rc, v, out = self.run_check("no-asan")
        self.assertEqual((rc, v), (1, ["UNCHECKED"]), out)
        self.assertIn("libclang_rt.asan", out)

    def test_a_run_past_the_limit_is_no_verdict(self):
        # Was ACCEPTED: timeout's exit 124 printed no fault.
        rc, v, out = self.run_check("slow", timeout=1)
        self.assertEqual((rc, v), (1, ["UNCHECKED"]), out)
        self.assertIn("after 1 s", out)

    def test_the_status_counts_holes_and_unchecked(self):
        rc, v, out = self.run_check("hole", "no-runtime", "clean", "rejected", "no-asan")
        self.assertEqual(rc, 3, out)
        self.assertEqual(v, ["HOLE", "UNCHECKED", "ACCEPTED", "REJECTED", "UNCHECKED"], out)
        self.assertIn("holes: 1", out)
        self.assertIn("unchecked: 2", out)

    def test_a_guard_refused_is_a_mismatch(self):
        # A guard the checker starts to refuse (agora #318: two of #265's,
        # refused on main for a day while CI saw `holes: 0`).
        rc, v, out = self.run_check("rejected=runs-clean")
        self.assertEqual((rc, v), (1, ["REJECTED"]), out)
        self.assertIn("MISMATCH", out)
        self.assertIn("mismatched: 1", out)

    def test_a_probe_running_clean_where_its_map_says_rejected_is_a_mismatch(self):
        rc, v, out = self.run_check("clean=rejected")
        self.assertEqual((rc, v), (1, ["ACCEPTED"]), out)
        self.assertIn("MISMATCH", out)

    def test_no_map_table_is_no_verdict(self):
        # A probe without its `// map:` line stops map.sh: no verdict was
        # compared, which is not a pass.
        rc, v, out = self.run_check("clean", map_line=False)
        self.assertEqual((rc, v), (1, ["UNCHECKED", "ACCEPTED"]), out)
        self.assertIn("map.sh failed", out)


if __name__ == "__main__":
    unittest.main()
