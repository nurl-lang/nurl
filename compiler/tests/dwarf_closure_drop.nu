// dwarf_closure_drop.nu — DWARF regression for the -O2 inliner crash.
//
// Compiling a program with `--debug` at -O2 used to crash clang in
// DwarfDebug::finalizeModuleInfo (DIE::getUnitDie) whenever the
// optimizer inlined a callee carrying debug info through a call site
// that had NO `!dbg` location. nurlc emitted three such inlinable
// calls without a location:
//   * the indirect closure call `call %fnptr(...)` (here: the drop
//     closure that `vec_free_with` invokes per element),
//   * the `__jdrop_*` journal thunk's call to `drop__*`, and
//   * the synthetic C-ABI `main` wrapper's call to `_nurl_main`.
// The inliner reparented the callee's scoped instructions into a
// subprogram-less / wrong-subprogram caller — "!dbg attachment points
// at wrong subprogram for function" — and DWARF emission null-deref'd.
//
// `vec_free_with` + a closure is the *deterministic* trigger (the small
// helper is always inlined, so the indirect call is always reparented).
//
// This is a BUILD-ONLY regression: the crash was at link time, so a
// binary that links at -O2 with --debug is the assertion (driven by
// tools/dwarf_test.sh). The plain corpus run also compiles + runs it.

$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

@ main → i {
    : ( Vec String ) xs ( vec_new [String] )
    ( vec_push [String] xs ( string_from `a` ) )
    ( vec_push [String] xs ( string_from `bb` ) )
    ( vec_push [String] xs ( string_from `ccc` ) )
    : ~ i total 0
    // The closure runs per element (indirect call inside vec_free_with).
    ( vec_free_with [String] xs \ String s → v {
        = total + total ( string_len s )
        ( string_free s )
    } )
    ( nurl_print `total_len=` )
    ( nurl_print_int total )
    ( nurl_print `\n` )
    ^ 0
}
