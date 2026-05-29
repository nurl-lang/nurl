// should_warn_param_shadow.nu — exercises the docs/GOTCHAS.md item 3
// foot-gun pattern: a `:` binding declares a name that matches one of
// the enclosing function's parameters. The classic case is the one
// from the gotcha doc: `: i z + z 7` where `z` is a parameter. The
// RHS reads the parameter `z`, then the new `z` shadows from this
// line onward — any later read silently rebinds.
//
// Post-fix (compiler v2.1+): a non-fatal `warning:` line is emitted
// to stderr at the binding site. Compile + link + run still succeed
// (this is a SOFT diagnostic, not a compile error) so legacy code
// keeps building. The `WARNINGS` baseline block in
// compiler/tests/correct.txt captures the exact diagnostic text.
//
// Negative control: `fine` deliberately uses an unrelated binding
// name `zz` so the inline check confirms no spurious warning is
// fired on the non-shadowing path.

@ shadowing i z → i {
    : i z + z 7  // ← warns: 'z' shadows parameter z
    ^ z
}

@ fine i z → i {
    : i zz + z 7  // unrelated name, no warning
    ^ zz
}

@ main → i {
    // Print BOTH paths so the baseline snapshots both numerical
    // results (730 for the shadowing path, 730 for the non-shadowing
    // path — same arithmetic, different lexical hygiene).
    ( nurl_print `shadow=` )
    ( nurl_print ( nurl_str_int ( shadowing 723 ) ) )
    ( nurl_print `\n` )
    ( nurl_print `fine=` )
    ( nurl_print ( nurl_str_int ( fine 723 ) ) )
    ( nurl_print `\n` )
    ^ 0
}
