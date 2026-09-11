#!/usr/bin/env python3
# Copyright (c) 2026 The NURL Project Developers
# SPDX-License-Identifier: MIT OR Apache-2.0
"""One invariant over many spellings: a source file that still declares
`@ main` either fails to compile, or the module it produces defines main.

Nine parser defects found on 2026-09-11 shared a single shape. A construct
the grammar allows was handled by an ad-hoc token skip rather than by the
path that parses it, and the skip ran past the end of the declaration: a
binding's initialiser that was a block, a global constant with no value, a
struct or generic function with no body, a `:` followed by something else.
Each swallowed the declaration after it. The compiler exited 0 and the only
report — when there was one at all — came from the linker or from clang,
with no NURL source location.

The corpus pins each fix with its own rejection fixture. This pins the
CLASS: every declaration and statement form below is checked against the
same invariant, so a new parser path that skips instead of reporting fails
here even in a spelling nobody thought to write a fixture for.

A form listed as `compiles` must produce main; a form listed as `rejects`
must exit 1. Nothing may exit 0 without main.
"""
import os
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
NURLC = os.environ.get("NURLC", os.path.join(ROOT, "build", "nurlc"))

MAIN = """
@ main → i {
    ( nurl_print `MAIN RAN\\n` )
    ^ 0
}
"""

# (name, source prefix placed before main, expectation)
DECLARATIONS = [
    # ── ':' — struct, enum, global constant ──────────────────────────
    ("const_complete",        ": i MAX 10",                     "compiles"),
    ("const_folded",          ": i SECS * * 60 60 24",          "compiles"),
    ("const_no_value",        ": i MAX",                        "rejects"),
    ("const_no_name",         ": i",                            "rejects"),
    ("struct_complete",       ": Pt { i x i y }",               "compiles"),
    ("struct_no_body",        ": Pt",                           "rejects"),
    ("generic_struct",        ": Box [T] { T v i tag }",        "compiles"),
    ("generic_struct_no_body", ": Box [T]",                     "rejects"),
    ("generic_struct_unclosed", ": Box [T { T v }",             "rejects"),
    ("enum_complete",         ": | Color { Red Green }",        "compiles"),
    ("enum_no_body",          ": | Color",                      "rejects"),
    ("colon_junk",            ": 42",                           "rejects"),
    # ── '@' — functions ──────────────────────────────────────────────
    ("fn_complete",           "@ f → i { ^ 1 }",                "compiles"),
    ("fn_no_body",            "@ f → i",                        "rejects"),
    ("fn_empty_body_value",   "@ f → i {}",                     "rejects"),
    ("fn_empty_body_void",    "@ f → v {}",                     "compiles"),
    ("fn_dup_param",          "@ f i a i a → i { ^ a }",        "rejects"),
    ("fn_param_no_name",      "@ f i → i { ^ 0 }",              "rejects"),
    ("generic_fn",            "@ g [T] T x → T { ^ x }",        "compiles"),
    ("generic_fn_no_body",    "@ g [T] → T",                    "rejects"),
    ("generic_fn_unclosed",   "@ g [T x → T { ^ x }",           "rejects"),
    # ── '&' / '%' / '$' ──────────────────────────────────────────────
    ("ffi_complete",          "& `libm` @ cbrt f x → f",        "compiles"),
    ("trait_empty",           "% Show { }",                     "compiles"),
    ("trait_no_body",         "% Show",                         "rejects"),
    ("impl_no_body",          "% Show i",                       "rejects"),
    ("import_missing",        "$ `no_such_module.nu`",          "rejects"),
]

# Statement forms, placed inside main's body ahead of the print.
STATEMENTS = [
    ("loop_body",        "~ < k 3 { = k + k 1 }",                  "compiles"),
    ("cond_empty_arms",  "? > k 0 { } { }",                        "compiles"),
    ("defer_empty",      "; { }",                                  "compiles"),
    ("match_no_arms",    "?? k { }",                               "rejects"),
    ("match_default",    "?? k { _ → { } }",                       "compiles"),
    ("select_no_arms",   "?? { }",                                 "rejects"),
    ("bind_void_cond",   ": i x ? T { } { }",                      "rejects"),
    ("bind_block",       ": i x { 7 }",                            "compiles"),
    ("bind_block_empty", ": i x { }",                              "rejects"),
    ("foreach_slice",    ": [i xs [i | 1 2 3]\n    ~ e xs { = k + k e }", "compiles"),
    ("foreach_scalar",   "~ e k { = k 1 }",                        "rejects"),
]

STMT_TEMPLATE = """@ main → i {
    : ~ i k 0
    %s
    ( nurl_print `MAIN RAN\\n` )
    ^ 0
}
"""


class DeclarationForms(unittest.TestCase):
    def compile_source(self, src):
        with tempfile.NamedTemporaryFile("w", suffix=".nu", delete=False,
                                         dir=tempfile.gettempdir()) as f:
            f.write(src)
            path = f.name
        try:
            return subprocess.run([NURLC, path], capture_output=True, timeout=60)
        finally:
            os.unlink(path)

    def check(self, name, src, expectation):
        r = self.compile_source(src)
        emitted = b"define i32 @main(" in r.stdout
        if expectation == "rejects":
            self.assertEqual(
                r.returncode, 1,
                f"{name}: expected a diagnostic, got exit {r.returncode}\n"
                f"{r.stderr.decode('utf-8', 'replace')[:400]}")
            self.assertTrue(
                r.stderr.strip(),
                f"{name}: rejected with no message at all")
        else:
            self.assertEqual(
                r.returncode, 0,
                f"{name}: expected it to compile\n"
                f"{r.stderr.decode('utf-8', 'replace')[:400]}")
        # The invariant that binds both columns: never a clean exit whose
        # module has lost the main the source still declares.
        if r.returncode == 0:
            self.assertTrue(
                emitted,
                f"{name}: compiled cleanly but emitted no main — the "
                f"declaration under test swallowed it")

    def test_declaration_forms(self):
        for name, decl, expectation in DECLARATIONS:
            with self.subTest(form=name):
                self.check(name, decl + "\n" + MAIN, expectation)

    def test_statement_forms(self):
        for name, stmt, expectation in STATEMENTS:
            with self.subTest(form=name):
                self.check(name, STMT_TEMPLATE % stmt, expectation)


if __name__ == "__main__":
    unittest.main(verbosity=2)
