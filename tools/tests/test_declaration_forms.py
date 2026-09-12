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

The 2026-09-12 sweep continued into the surfaces that were left: the
`$`-import surface, generic instantiation, `%Trait` objects, the
`inout` / `sink` conventions and the `pub` boundary. It found five more,
and every one is the same question answered in one spelling and not the
other:

  * a generic STRUCT applied to the wrong number of type arguments was
    never counted, though the generic FUNCTION call path has counted for
    years. Too few leaves a parameter unsubstituted in the emitted type;
    too many mangles the definition from the declared parameters and each
    reference from all of them, so the reference names a type nothing
    defines. Both exit 0 and only clang objects.
  * `%Name` in a type position never checked that Name is a declared
    trait — the last type position still missing the check that closed
    `Z NoSuchType`.
  * a default value was never checked against its parameter on the
    POSITIONAL fill path: `@ show f x = 1` called `( show )` passed an
    integer register where the callee reads a float one and printed 0.
    The explicit-argument path has rejected that for years.
  * a default on an `inout` parameter compiled and passed the literal
    where the callee expects an address — a clean compile and a segfault.
    The grammar names four places a default is unavailable; the other
    three already rejected one.
  * `pub` on a `$` import was read and discarded in silence, so a file
    whose only `pub` sat on its import never entered strict visibility —
    while `simd` and `inline` in that exact position are diagnostics.
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
    # ── generic instantiation at a TYPE position ─────────────────────
    # A generic names a family of types; the type arguments pick one.
    # A wrong COUNT is not a smaller mistake than a wrong name: too few
    # leaves the surplus parameter in the emitted type (`%P__i64 =
    # type { i64, %V }`), too many mangles the definition and the
    # reference differently (`%Box__i64` defined, `%Box__i64__f64`
    # referenced). The generic FUNCTION call path counts; this one did
    # not.
    ("gstruct_targs_ok",      ": Box [T] { T v }\n@ f ( Box i ) b → i { ^ 1 }", "compiles"),
    ("gstruct_targs_none",    ": Box [T] { T v }\n@ f Box b → i { ^ 1 }",       "rejects"),
    ("gstruct_targs_few",     ": P [K V] { K a V b }\n@ f ( P i ) x → i { ^ 1 }", "rejects"),
    ("gstruct_targs_many",    ": Box [T] { T v }\n@ f ( Box i f ) x → i { ^ 1 }", "rejects"),
    ("gstruct_targs_nested",  ": Box [T] { T v }\n@ f ( Box ( Box i f ) ) x → i { ^ 1 }", "rejects"),
    # ── '%Trait' — the dynamic trait object in a type position ───────
    # The name must be a trait DECLARED with a body. Nothing checked it:
    # parse_type_dyn runs its object-safety check only when the trait is
    # already known, and check_type_known skipped `%dyn.<Trait>` outright
    # on the claim that parse_type_dyn had validated it.
    ("dyn_type_ok",           "% Sp [T] { @ speak T s → i }\n@ f %Sp d → i { ^ 1 }", "compiles"),
    ("dyn_type_field",        "% Sp [T] { @ speak T s → i }\n: H { %Sp d }", "compiles"),
    ("dyn_type_unknown",      "@ f %NoTrait d → i { ^ 1 }",     "rejects"),
    ("dyn_type_field_unknown", ": H { %NoTrait d }",            "rejects"),
    ("dyn_type_is_struct",    ": Dog { i p }\n@ f %Dog d → i { ^ 1 }", "rejects"),
    # ── default parameter values ────────────────────────────
    # A default is spliced into the argument list of every call that
    # omits it, so it is an argument and owes an argument's agreement.
    # `g` supplies that call: every row but the two convention rows is
    # checked at the call site, not at the declaration.
    ("default_ok",            "@ f i a i b = 2 → i { ^ + a b }\n@ g → i { ^ ( f 1 ) }", "compiles"),
    ("default_float_for_int", "@ f i a i b = 1.5 → i { ^ b }\n@ g → i { ^ ( f 1 ) }", "rejects"),
    ("default_int_for_float", "@ f i a f b = 1 → f { ^ b }\n@ g → f { ^ ( f 1 ) }", "rejects"),
    ("default_str_for_int",   "@ f i a i b = `x` → i { ^ b }\n@ g → i { ^ ( f 1 ) }", "rejects"),
    ("default_int_for_str",   "@ f i a s b = 1 → i { ^ a }\n@ g → i { ^ ( f 1 ) }", "rejects"),
    # The named-argument spelling reaches the defaults by a different
    # path; it must answer the same.
    ("default_named_mismatch", "@ f i a f b = 1 → f { ^ b }\n@ g → f { ^ ( f a: 1 ) }", "rejects"),
    # ── the callee of a call ─────────────────────────────────────────
    # A call's first word is the thing being called, and only a function
    # or something function-TYPED can be it. gen_ident has refused a name
    # that resolves to nothing for years; gen_call emitted `call @name`
    # for a name that resolves to a VALUE — an undefined global for a
    # local, and for a const a call into the constant's own storage,
    # which clang accepts and which segfaults.
    ("call_const_value",      ": i MAX 10\n@ g → i { ( MAX ) ^ 0 }", "rejects"),
    ("call_variant_value",    ": | C { Red Green }\n@ g → i { ( Red ) ^ 0 }", "rejects"),
    ("call_closure_binding",  "@ g → i { : (@ i i) f \\ i x → i { ^ x }\n : i q ( f 5 ) ^ q }", "compiles"),
    ("call_closure_param",    "@ run ( @ i i ) h i x → i { ^ ( h x ) }", "compiles"),
    # The grammar names four places a default is not available. All four.
    ("default_on_inout",      "@ f inout i b = 0 → v { = b 1 }", "rejects"),
    ("default_on_sink",       "@ f sink s b = `x` → i { ^ 1 }",  "rejects"),
    ("default_on_generic",    "@ f [T] T a i b = 2 → i { ^ b }", "rejects"),
    ("default_on_ffi",        "& `libc` @ abs i x = 0 → i",      "rejects"),
]

# The '$'-import surface. Each row compiles `a.nu` with `lib.nu` written
# beside it, so the import resolves from the importing file's own
# directory and the test needs no particular working directory.
#
# `pub` is the point of the last three rows: the grammar excludes
# import_decl from the visibility prefix, and it was read-and-cleared in
# silence — so a file whose only `pub` sat on its import stayed in legacy
# visibility with every function globally callable, and said nothing.
# `simd` and `inline` in the same position have been diagnostics since
# grammar v2.6.
IMPORTS = [
    ("import_plain",         "$ `lib.nu`",            "compiles"),
    ("import_no_ext",        "$ `lib`",               "compiles"),
    ("import_alias",         "$ `lib.nu` m",          "compiles"),
    ("import_twice",         "$ `lib.nu`\n$ `lib.nu`", "compiles"),
    # The duplicate-include guard keys on the RESOLVED file, so two
    # spellings of one path include it once — not twice, which would
    # redefine everything in it.
    ("import_twice_spelled", "$ `lib`\n$ `lib.nu`",   "compiles"),
    ("import_self",          "$ `a.nu`",              "compiles"),
    ("import_missing",       "$ `no_such_module.nu`", "rejects"),
    ("import_empty_path",    "$ ``",                  "rejects"),
    ("import_pub",           "pub $ `lib.nu`",        "rejects"),
    ("import_simd",          "simd $ `lib.nu`",       "rejects"),
    ("import_inline",        "inline $ `lib.nu`",     "rejects"),
]

FFI = [
    ("ffi_plain",          "& `libc` @ xhelp s msg → i",                  "compiles"),
    ("ffi_no_param_name",  "& `libm` @ xhelp f → f",                      "compiles"),
    ("ffi_no_params",      "& `libc` @ xhelp → i",                        "compiles"),
    ("ffi_variadic",       "& `libc` @ xpf s fmt ... → i",                "compiles"),
    ("ffi_variadic_only",  "& `libc` @ xpf ... → i",                      "compiles"),
    ("ffi_no_arrow",       "& `libc` @ xhelp s msg",                      "rejects"),
    ("ffi_no_name",        "& `libc` @ → i",                              "rejects"),
    ("ffi_no_at",          "& `libc` xhelp s msg → i",                    "rejects"),
    ("ffi_unknown_ret",    "& `libc` @ xhelp s msg → NoSuchType",         "rejects"),
    ("ffi_unknown_param",  "& `libc` @ xhelp NoSuchType m → i",           "rejects"),
    ("ffi_default_value",  "& `libc` @ xhelp s msg = 1 → i",              "rejects"),
    ("ffi_generic",        "& `libc` @ xhelp [T] T msg → i",              "rejects"),
    ("ffi_body",           "& `libc` @ xhelp s msg → i { ^ 0 }",          "rejects"),
    ("ffi_redecl_same",    "& `libc` @ xhelp i a → i\n& `libc` @ xhelp i a → i", "compiles"),
    ("ffi_redecl_diff",    "& `libc` @ xhelp i a → i\n& `libc` @ xhelp f a → i", "rejects"),
    # The '...' marker is LAST and appears once. The parameter loop took
    # one wherever it landed, and the `declare` line and the call-site
    # signature then disagreed about what the declaration said: a trailing
    # parameter emitted `(i8*, ..., i64)` and a second marker
    # `(i8*, ..., ...)`, both of which llvm-as rejects. A LEADING marker
    # was overwritten in the declare and kept at the call site, so the
    # module declared `@xpf(i8*)` and called `xpf(...)`.
    ("ffi_ellipsis_mid",   "& `libc` @ xpf s fmt ... i n → i",            "rejects"),
    ("ffi_ellipsis_twice", "& `libc` @ xpf s fmt ... ... → i",            "rejects"),
    ("ffi_ellipsis_first", "& `libc` @ xpf ... s fmt → i",                "rejects"),
    # The library name is what turns a missing dev package into a compile
    # error. An empty one did not PASS that gate, it skipped it.
    ("ffi_empty_library",  "& `` @ xhelp i a → i",                        "rejects"),
]

# Call sites against an FFI declaration, placed inside main.
FFI_CALLS = [
    ("ffi_call_ok",        "& `libc` @ xhelp i a → i",  ": i r ( xhelp 1 )",       "compiles"),
    ("ffi_call_few",       "& `libc` @ xhelp i a → i",  ": i r ( xhelp )",         "rejects"),
    ("ffi_call_many",      "& `libc` @ xhelp i a → i",  ": i r ( xhelp 1 2 )",     "rejects"),
    ("ffi_call_literal",   "& `libc` @ xhelp s a → i",  ": i r ( xhelp 5 )",       "rejects"),
    ("var_call_tail",      "& `libc` @ xpf s f ... → i", ": i r ( xpf `x` 1 2 3 )", "compiles"),
    ("var_call_prefix",    "& `libc` @ xpf s f ... → i", ": i r ( xpf `x` )",      "compiles"),
    # '...' makes the TAIL optional, never the fixed prefix. A variadic
    # symbol gets no `__arity`, so the call-site count check skipped it
    # entirely — including the minimum the declaration does state.
    ("var_call_no_fixed",  "& `libc` @ xpf s f ... → i", ": i r ( xpf )",          "rejects"),
    ("var_call_literal",   "& `libc` @ xpf s f ... → i", ": i r ( xpf 5 5 )",      "rejects"),
]

# '\\' propagation, the '?T' / '!T E' surfaces, and '#' casts. Each row is
# a whole program: these forms are about a function's RETURN type, which
# the statement template fixes.
TRY_AND_CAST = [
    ("try_res_in_res",  "@ p i a → !i i { ^ @ !i i { T a } }\n"
                        "@ g → !i i { : i v \\ ( p 1 ) ^ @ !i i { T v } }", "compiles"),
    ("try_opt_in_opt",  "@ p i a → ?i { ^ @ ?i { T a } }\n"
                        "@ g → ?i { : i v \\ ( p 1 ) ^ @ ?i { T v } }",     "compiles"),
    ("try_err_match",   "@ p i a → !i s { ^ @ !i s { T a } }\n"
                        "@ g → !i s { : i v \\ ( p 1 ) ^ @ !i s { T v } }", "compiles"),
    ("try_err_differ",  "@ p i a → !i s { ^ @ !i s { T a } }\n"
                        "@ g → !i i { : i v \\ ( p 1 ) ^ @ !i i { T v } }", "rejects"),
    # The enclosing function must be able to CARRY the failure. When it
    # returned anything else the fail path fell to `zeroinitializer`,
    # which is not propagation: `→ i` returned 0 and `→ s` returned a
    # null pointer that segfaulted the moment it was printed.
    ("try_res_in_int",  "@ p i a → !i i { ^ @ !i i { T a } }\n"
                        "@ g → i { : i v \\ ( p 1 ) ^ v }",                 "rejects"),
    ("try_opt_in_int",  "@ p i a → ?i { ^ @ ?i { T a } }\n"
                        "@ g → i { : i v \\ ( p 1 ) ^ v }",                 "rejects"),
    ("try_res_in_str",  "@ p i a → !i i { ^ @ !i i { T a } }\n"
                        "@ g → s { : i v \\ ( p 1 ) ^ `x` }",               "rejects"),
    ("try_res_in_void", "@ p i a → !i i { ^ @ !i i { T a } }\n"
                        "@ g → v { : i v \\ ( p 1 ) }",                     "rejects"),
    # Both shapes start `{ i1, `, so "can it carry a failure" accepts
    # either — and the fail path then zeroes the OTHER shape: an option
    # tried in a result function returns Err with an invented payload of
    # 0, a result tried in an option function drops the error entirely.
    ("try_res_in_opt",  "@ p i a → !i i { ^ @ !i i { T a } }\n"
                        "@ g → ?i { : i v \\ ( p 1 ) ^ @ ?i { T v } }",     "rejects"),
    ("try_opt_in_res",  "@ p i a → ?i { ^ @ ?i { T a } }\n"
                        "@ g → !i i { : i v \\ ( p 1 ) ^ @ !i i { T v } }", "rejects"),
    ("try_over_int",    "@ p i a → i { ^ a }\n"
                        "@ g → !i i { : i v \\ ( p 1 ) ^ @ !i i { T v } }", "rejects"),
    # '?T' / '!T E' literals: field 0 is the TAG.
    ("opt_lit_some",    "@ g → ?i { ^ @ ?i { T 5 } }",                        "compiles"),
    ("opt_lit_none",    "@ g → ?i { ^ @ ?i { F } }",                          "compiles"),
    ("opt_lit_no_tag",  "@ g → ?i { ^ @ ?i { 5 } }",                          "rejects"),
    ("opt_lit_extra",   "@ g → ?i { ^ @ ?i { T 5 6 } }",                      "rejects"),
    ("res_lit_ok",      "@ g → !i i { ^ @ !i i { T 5 } }",                    "compiles"),
    ("res_lit_err",     "@ g → !i i { ^ @ !i i { F 5 } }",                    "compiles"),
    ("res_lit_no_tag",  "@ g → !i i { ^ @ !i i { 5 } }",                      "rejects"),
    # An option and a result each have exactly two arms. The enum
    # spelling of a non-exhaustive match has been rejected for years;
    # these two fell through check_exhaustive's `__variants` lookup and
    # the uncovered path became `undef` in the join phi.
    ("match_opt_full",  "@ p i a → ?i { ^ @ ?i { T a } }\n"
                        "@ g → i { : ?i o ( p 1 ) ^ ?? o { T v → v F → 0 } }", "compiles"),
    ("match_opt_wild",  "@ p i a → ?i { ^ @ ?i { T a } }\n"
                        "@ g → i { : ?i o ( p 1 ) ^ ?? o { T v → v _ → 0 } }", "compiles"),
    ("match_opt_no_f",  "@ p i a → ?i { ^ @ ?i { T a } }\n"
                        "@ g → i { : ?i o ( p 1 ) ^ ?? o { T v → v } }",       "rejects"),
    ("match_opt_no_t",  "@ p i a → ?i { ^ @ ?i { T a } }\n"
                        "@ g → i { : ?i o ( p 1 ) ^ ?? o { F → 0 } }",         "rejects"),
    ("match_res_no_f",  "@ p i a → !i i { ^ @ !i i { T a } }\n"
                        "@ g → i { : !i i r ( p 1 ) ^ ?? r { T v → v } }",     "rejects"),
    ("match_res_okerr", "@ p i a → !i i { ^ @ !i i { T a } }\n"
                        "@ g → i { : !i i r ( p 1 ) ^ ?? r { Ok v → v F e → e } }", "rejects"),
    # '#' converts a value; it does not reinterpret one aggregate as
    # another. The named-struct source reached the final no-op because
    # `%Struct` sources are handled above ONLY for an integer target.
    ("cast_widen",      "@ g → i { ^ # i64 # u8 5 }",                          "compiles"),
    ("cast_struct_f0",  ": Pt { i x i y }\n@ m → Pt { ^ @ Pt { 1 2 } }\n"
                        "@ g → i { ^ # i ( m ) }",                             "compiles"),
    ("cast_same_struct", ": Pt { i x i y }\n@ m → Pt { ^ @ Pt { 1 2 } }\n"
                        "@ g → Pt { ^ # Pt ( m ) }",                           "compiles"),
    ("cast_struct_other", ": Pt { i x i y }\n: Q { i a i b i c }\n"
                        "@ m → Pt { ^ @ Pt { 1 2 } }\n@ g → Q { ^ # Q ( m ) }", "rejects"),
    ("cast_unknown_ty", "@ g → i { ^ # NoSuchType 5 }",                        "rejects"),
    ("cast_agg_source", "@ p i a → ?i { ^ @ ?i { T a } }\n"
                        "@ g → i { ^ # i ( p 1 ) }",                           "rejects"),
    # A binding declared `*T` wants an ADDRESS. An aggregate VALUE fell
    # through all six clauses of the never-legal-mix battery: the integer
    # clause knows only integers, the nominal clause requires neither side
    # to be a pointer, and the pointer clause runs the other direction.
    # Found by deleting one '*' from a cast (`# *Node x` → `# Node x`).
    ("bind_ptr_from_ptr",  ": Node { i a i b }\n@ g → i { : *Node p # *Node 0 ^ 0 }", "compiles"),
    ("bind_ptr_from_val",  ": Node { i a i b }\n@ g → i { : *Node p # Node 0 ^ 0 }",  "rejects"),
    ("bind_ptr_from_opt",  "@ p i a → ?i { ^ @ ?i { T a } }\n"
                           "@ g → i { : *i q ( p 1 ) ^ 0 }",                    "rejects"),
    ("bind_ptr_from_slice", "@ g → i { : [i xs [i | 1 2 3]\n    : *i q xs ^ 0 }", "rejects"),
]

# Trait / impl / marker subjects. An impl's SUBJECT is a type position.
IMPLS = [
    ("impl_known",        ": Pt { i x }\n% Boxed [T] {\n    @ unwrap T self → i\n}\n"
                          "% Boxed Pt { @ unwrap Pt self → i { ^ . self x } }", "compiles"),
    ("impl_unknown_type", "% Boxed [T] {\n    @ unwrap T self → i\n}\n"
                          "% Boxed NoSuchType { @ unwrap i self → i { ^ 0 } }", "rejects"),
    # A marker asserts what the structural derivation cannot see. On a
    # misspelled subject it asserted it about nothing at all, silently —
    # and the type it was written to protect stayed Send.
    ("marker_known",      ": Db { s handle }\n% NotSend Db { }",              "compiles"),
    ("marker_send_known", ": Db { s handle }\n% Send Db { }",                 "compiles"),
    ("marker_unknown",    ": Db { s handle }\n% NotSend Dbb { }",             "rejects"),
    ("marker_sync_unknown", ": Db { s handle }\n% Sync Nope { }",             "rejects"),
]

IMPORT_LIB = "@ lib_helper → i { ^ 7 }\n"

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
    # A binding whose initialiser is the `^` that was meant to be the
    # function's return. The reading is correct — the binding takes the
    # return as its value and the body has none left — and the IR on the
    # way there was not: the store landed after the block's terminator.
    ("bind_value_is_return", ": i a",                             "rejects"),
    # The legal twin, which the '^'-vs-'^^' warning keeps compiling:
    # `^ k` returns and the binding is dead code, but the block is
    # well-formed.
    ("bind_value_is_return_live", ": i x ^ k\n    ^ x",            "compiles"),
    # An element INDEX is an integer. The read side has always said so
    # ('. xs 1.5' is "expected a field name or an index"); the five
    # index-STORE paths never asked, and emitted a getelementptr with a
    # double index. The spelling that reaches it is a MISSING index.
    ("elem_store_index_ok",    ": ~ [i xs [i | 1 2 3]\n    = . xs 0 7",   "compiles"),
    ("elem_store_index_expr",  ": ~ [i xs [i | 1 2 3]\n    = . xs + k 1 7", "compiles"),
    ("elem_store_index_float", ": ~ [i xs [i | 1 2 3]\n    = . xs 1.5 7",  "rejects"),
    ("elem_store_index_str",   ": ~ [i xs [i | 1 2 3]\n    = . xs `x` 7",  "rejects"),
    ("elem_store_index_gone",  ": ~ [i xs [i | 1 2 3]\n    = . xs   1.5",  "rejects"),
    # A call whose callee names a local value, in the two shapes the
    # token-deletion sweep produces by deleting a callee name.
    ("call_local_value",  "( k )",                                  "rejects"),
    ("call_local_value_args", "( k 1 2 )",                          "rejects"),
    ("call_slice_value",  ": [i xs [i | 1 2 3]\n    ( xs )",        "rejects"),
    ("call_struct_value", ": Pt p @ Pt { 1 2 }\n    ( p )",         "rejects"),
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
        self.verdict(name, self.compile_source(src), expectation)

    def clang_verdict(self, stdout):
        """The second question, asked of everything that compiles: does
        clang accept the module? "Exit 0 and main is there" is a weak
        invariant — most of what the 2026-09-12 sweeps found KEEPS main
        and emits IR only the LLVM parser or verifier objects to. Asking
        it here is what lets a hand-written row see those.

        Note `clang -c`, not `clang -fsyntax-only -x ir`: the latter does
        not parse the IR at all and exits 0 on a module llvm-as rejects.
        A probe written that way reported every one of these forms clean.
        A missing clang is not a finding — skip the question then."""
        with tempfile.TemporaryDirectory() as d:
            ll = os.path.join(d, "m.ll")
            with open(ll, "wb") as f:
                f.write(stdout)
            try:
                c = subprocess.run(
                    ["clang", "-c", "-Wno-override-module", ll,
                     "-o", os.path.join(d, "m.o")],
                    capture_output=True, timeout=120)
            except (FileNotFoundError, subprocess.TimeoutExpired):
                return None
            if c.returncode == 0:
                return None
            errs = [l for l in c.stderr.decode("utf-8", "replace").splitlines()
                    if "error:" in l]
            return errs[0] if errs else "clang rejected the module"

    def verdict(self, name, r, expectation):
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
            # …and the stronger one: a compiler that exits 0 owes valid IR.
            why = self.clang_verdict(r.stdout)
            self.assertIsNone(
                why,
                f"{name}: compiled cleanly but emitted IR clang rejects — "
                f"{why}")

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

    def test_ffi_forms(self):
        for name, decl, expectation in FFI:
            with self.subTest(form=name):
                self.check(name, decl + "\n" + MAIN, expectation)

    def test_ffi_call_forms(self):
        for name, decl, stmt, expectation in FFI_CALLS:
            with self.subTest(form=name):
                src = (decl + "\n@ main → i {\n    " + stmt +
                       "\n    ( nurl_print `MAIN RAN\\n` )\n    ^ 0\n}\n")
                self.check(name, src, expectation)

    def test_try_and_cast_forms(self):
        # `g` must be CALLED or the whole declaration is dead-code
        # eliminated and the form under test never reaches codegen.
        for name, decl, expectation in TRY_AND_CAST:
            with self.subTest(form=name):
                src = (decl + "\n@ main → i {\n    ( g )\n"
                       "    ( nurl_print `MAIN RAN\\n` )\n    ^ 0\n}\n")
                self.check(name, src, expectation)

    def test_impl_forms(self):
        for name, decl, expectation in IMPLS:
            with self.subTest(form=name):
                self.check(name, decl + "\n" + MAIN, expectation)

    def test_import_forms(self):
        # A real directory with a real sibling: an import resolves from
        # the importing file's own directory first, so these rows say
        # nothing about the working directory the test was started in.
        for name, decl, expectation in IMPORTS:
            with self.subTest(form=name):
                with tempfile.TemporaryDirectory() as d:
                    with open(os.path.join(d, "lib.nu"), "w") as f:
                        f.write(IMPORT_LIB)
                    main = os.path.join(d, "a.nu")
                    with open(main, "w") as f:
                        f.write(decl + "\n" + MAIN)
                    r = subprocess.run([NURLC, "a.nu"], capture_output=True,
                                       timeout=60, cwd=d)
                self.verdict(name, r, expectation)


if __name__ == "__main__":
    unittest.main(verbosity=2)
