// should_fail_unbalanced_braces.nu — an unbalanced-brace function body
// must be REJECTED by the front-end, not silently miscompiled.
//
// Here `f`'s `~` loop body is closed by `}}` — one `}` too many. The
// extra close ends `f`'s body early, leaving `^ ( g x )` and the real
// closing `}` stranded at the top level. The decl loop used to silently
// advance past such stray tokens, so `f` compiled to a truncated body
// (an `undef` return) AND the scan_fn_sigs pre-pass desynced and stopped
// registering every later function — a forward call to `g` then fell
// back to the `i64` return-type default and only clang rejected the
// mismatched `ret`. nurlc itself exited 0. (Surfaced building
// stdlib/ext/yaml.nu — see GOTCHAS / project memory.)
//
// The fix makes any non-declaration token at the top level a hard error,
// turning the whole class into a diagnostic at the first leaked token.
// Expect COMPILE FAIL.

@ f i n → i {
    : ~ i x 0
    ~ < n x {
        ? > x 5 { = x + x 1 } {}
    } }
^ ( g x )
}

@ g i n → i {
    ^ + n 1
}

@ main → i {
    ^ ( f 3 )
}
