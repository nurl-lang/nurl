// diag_stray_rbrace_top_level.nu — a stray '}' after a complete
// function must fire the top-level "expected a declaration" error.
// Pins the diagnostic's text: should_fail_unbalanced_braces used to be
// the only program reaching this site, and its truncated body now
// (correctly) trips the fall-off no-value check first, so this test
// keeps the top-level site spoken for with a body that has nothing
// wrong of its own.

@ f → i {
    ^ 1
}

}

@ main → i {
    ^ ( f )
}
