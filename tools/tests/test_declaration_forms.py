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

The 2026-09-12 sweep extended the table past declarations and simple
statements, into expression position, trait and impl bodies, match and
select arms, and the block terminators. It found four more of the same
shape, three of which the invariant above cannot see because they keep
main and fail later: `Z NoSuchType` emitted a getelementptr on a type
nothing declares; an or-pattern alternative that named no variant emitted
a load of a global nothing defines; a `break`/`continue` inside a `;`
defer block branched into the loop exit the defer chain had already left,
so the program ran forever; and an impl was never checked against the
trait it names — a missing required method, a wrong arity, wrong parameter
types or a wrong return type all compiled, and `dyn` dispatch then called
through a vtable built from the DECLARED signature.
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
    # A template's signature ends at its return type, not at "the next '{'
    # anywhere in the file". With the old rule, a generic whose body brace was
    # missing collected the NEXT declaration's '{' as its own body opener and
    # swallowed that declaration whole — exit 0, no main, nothing on stderr.
    # Only the bounded form (`[T: Trait]`) reached that path, which is why no
    # hand-written spelling had found it; deleting one token did.
    ("generic_fn_bound",      "@ g [T : Send] T x → i { ^ 0 }", "compiles"),
    ("generic_fn_bound_no_body", "@ g [T : Send] T x → i   ^ 0 }", "rejects"),
    # ── '&' / '%' / '$' ──────────────────────────────────────────────
    ("ffi_complete",          "& `libm` @ cbrt f x → f",        "compiles"),
    ("trait_empty",           "% Show { }",                     "compiles"),
    ("trait_no_body",         "% Show",                         "rejects"),
    ("impl_no_body",          "% Show i",                       "rejects"),
    ("import_missing",        "$ `no_such_module.nu`",          "rejects"),
    # An impl must satisfy the trait it names: the trait has to exist, every
    # method it declares without a body has to be provided, and a provided
    # method has to have the signature the trait declares. `dyn` builds its
    # thunk from the DECLARATION, so a disagreement is a type confusion at
    # the call, not a local matter.
    ("impl_complete",         "% Sh { @ area i o → i }\n% Sh i { @ area i o → i { ^ * o 2 } }", "compiles"),
    ("impl_uses_default",     "% Sh { @ area i o → i { ^ o } }\n% Sh i { }", "compiles"),
    ("impl_overrides_default", "% Sh { @ area i o → i { ^ o } }\n% Sh i { @ area i o → i { ^ * o 2 } }", "compiles"),
    ("impl_missing_required", "% Sh { @ area i o → i }\n% Sh i { }", "rejects"),
    # An impl of a trait that is not DECLARED anywhere is the idiom, not an
    # error: `Drop`, `Ord` and `Show` are implemented with no declaration.
    # There is simply no contract to check for one.
    ("impl_undeclared_trait", "% NoSuchTrait i { @ f i o → i { ^ 1 } }", "compiles"),
    ("impl_ret_mismatch",     "% Sh { @ area i o → i }\n% Sh i { @ area i o → s { ^ `x` } }", "rejects"),
    ("impl_arity_mismatch",   "% Sh { @ area i o i k → i }\n% Sh i { @ area i o → i { ^ o } }", "rejects"),
    ("impl_param_mismatch",   "% Sh { @ area i o i k → i }\n% Sh i { @ area i o f k → i { ^ o } }", "rejects"),
    # A NON-generic trait's receiver slot is a placeholder each impl replaces
    # — `% Show { @ show i n → s }` is implemented for `i` and for `b` — so a
    # differing receiver there is the idiom, not a violation. In a GENERIC
    # trait the receiver is the type parameter, and substitution makes it
    # exact; `impl_generic_mismatch` covers that side.
    ("impl_receiver_placeholder", "% Sh { @ area i o → i }\n% Sh b { @ area b o → i { ^ ? o 1 0 } }", "compiles"),
    ("impl_generic_ok",       ": Dog { i n }\n% Sp [T] { @ speak T d → i }\n% Sp Dog { @ speak Dog d → i { ^ . d n } }", "compiles"),
    ("impl_generic_mismatch", ": Dog { i n }\n% Sp [T] { @ speak T d → i }\n% Sp Dog { @ speak Dog d → s { ^ `x` } }", "rejects"),
    # A trait body holds methods and associated types. Any other token used
    # to be skipped, and the skip is what made an UNTERMINATED body
    # dangerous: the scan stopped at the next declaration's closing brace
    # while the emit pass skipped balanced braces to end of file, so the two
    # disagreed about where the trait ended and `main` vanished with no
    # diagnostic at all. Found by deleting one '}' from a corpus program.
    ("trait_unterminated",    "% Sp [T] { @ speak T self → i\n: Dog { i pitch }\n% Sp Dog { @ speak Dog d → i { ^ . d pitch } }", "rejects"),
    ("trait_junk_in_body",    "% Sh { 42 }", "rejects"),
    ("trait_method_no_name",  "% Sh { @ → i }", "rejects"),
    ("trait_nested_decl",     "% Sh { : Pt { i x } }", "rejects"),
    ("impl_junk_in_body",     "% Sh { @ area i o → i }\n% Sh i { 42 }", "rejects"),
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
    # The pre-registered C-runtime surface is checked like an '&'-declared
    # symbol: arity, argument types, and a literal in a pointer position.
    ("builtin_ok",       "( nurl_print `x` )",                     "compiles"),
    ("builtin_null_ptr", "( nurl_print 0 )",                       "compiles"),
    ("builtin_arity",    "( nurl_print )",                         "rejects"),
    ("builtin_arity_hi", "( nurl_print `a` `b` )",                 "rejects"),
    ("builtin_float",    "( nurl_print 1.5 )",                     "rejects"),
    ("builtin_literal",  "( nurl_print 5 )",                       "rejects"),
    ("builtin_ptr_int",  "( nurl_print ( nurl_str_int `s` ) )",    "rejects"),
    # A field write gets the same check the read side has.
    ("field_store_ok",   ": ~ Pt q @ Pt { 1 2 }\n    = . q x 5",   "compiles"),
    ("field_store_bad",  ": ~ Pt q @ Pt { 1 2 }\n    = . q nope 5", "rejects"),
    # ── expression position ──────────────────────────────────────────
    # Every other type position runs the declared-type check; `Z` did not,
    # and emitted a getelementptr on an undeclared type.
    ("sizeof_base",      ": i q Z i",                              "compiles"),
    ("sizeof_struct",    ": i q Z Pt",                             "compiles"),
    ("sizeof_ptr",       ": i q Z *Pt",                            "compiles"),
    ("sizeof_unknown",   ": i q Z NoSuchType",                     "rejects"),
    ("sizeof_ptr_unknown", ": i q Z *NoSuchType",                  "rejects"),
    ("bin_one_operand",  ": i q + 1",                              "rejects"),
    ("not_no_operand",   ": i q !",                                "rejects"),
    ("cond_two_operands", ": i q ? > k 0 1",                       "rejects"),
    ("agg_over_fields",  ": Pt p @ Pt { 1 2 3 }",                  "rejects"),
    ("agg_unclosed",     ": Pt p @ Pt { 1 2",                      "rejects"),
    ("slice_no_bar",     ": [i ys [i 1 2 3]",                      "rejects"),
    ("slice_unclosed",   ": [i ys [i | 1 2 3",                     "rejects"),
    ("call_unclosed",    "( nurl_print `x`",                       "rejects"),
    ("closure_zero_param", ": (@ v) f \\ → v { }",               "compiles"),
    ("closure_empty_body", ": (@ i i) f \\ i x → i { }",         "rejects"),
    ("closure_dup_param",  ": (@ i i i) f \\ i a i a → i { ^ a }", "rejects"),
    # ── block terminators inside a ';' defer body ────────────────────
    # The defer chain runs DURING return, after the loop has exited. `^`
    # was rejected here; `break` and `continue` were not, and branched
    # back into the exit block the chain had just come from — an infinite
    # loop that compiled, exited 0 and printed forever.
    ("defer_return",     "; { ^ 1 }",                              "rejects"),
    ("defer_break",      "~ < k 3 { ; { break } = k + k 1 }",      "rejects"),
    ("defer_continue",   "~ < k 3 { ; { continue } = k + k 1 }",   "rejects"),
    ("defer_own_loop",   "; { ~ < k 3 { = k + k 1 } }",            "compiles"),
    # ── select arms ──────────────────────────────────────────────────
    ("select_arm_no_block", "?? { [i] k → o }",                    "rejects"),
    ("select_default_only", "?? { _ → { } }",                      "rejects"),
    ("select_two_defaults", "?? { _ → { } _ → { } }",              "rejects"),
]

# Match arms need an enum to match on; kept in their own template so the
# statement rows above stay in the context their expectations were set in.
MATCHES = [
    ("match_variant",      "?? c { Red → { } _ → { } }",           "compiles"),
    ("match_no_arms",      "?? c { }",                             "rejects"),
    ("match_unknown",      "?? c { Nope → { } _ → { } }",          "rejects"),
    ("match_nonexhaustive", "?? c { Red → { } }",                  "rejects"),
    ("match_dup_variant",  "?? c { Red → { } Red → { } _ → { } }", "rejects"),
    # The first name is checked against the enum's variants; an or-pattern
    # ALTERNATIVE was not, and emitted a load of a global nothing defines.
    ("match_or_known",     "?? c { Red | Green → { } _ → { } }",   "compiles"),
    ("match_or_unknown",   "?? c { Red | Nope → { } _ → { } }",    "rejects"),
    ("match_or_repeat",    "?? c { Red | Red → { } _ → { } }",     "rejects"),
]

MATCH_TEMPLATE = """: | Color { Red Green Blue }

@ main → i {
    : Color c @ Color { Green }
    %s
    ( nurl_print `MAIN RAN\\n` )
    ^ 0
}
"""

STMT_TEMPLATE = """: Pt { i x i y }

@ main → i {
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

    def test_match_forms(self):
        for name, stmt, expectation in MATCHES:
            with self.subTest(form=name):
                self.check(name, MATCH_TEMPLATE % stmt, expectation)


if __name__ == "__main__":
    unittest.main(verbosity=2)
