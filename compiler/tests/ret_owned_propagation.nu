// Test: owned-string return propagation through `^ ( call )` (critic.md
// A4 follow-on). `__fn_ret_str_owned__` was only set when the return
// expression was a bare identifier already in `__owned_strings__`;
// a helper returning `^ ( nurl_str_cat … )` directly was never marked
// `__ret_owned=str`, so `: s x ( helper )` at the caller never
// registered a drop — composing string helpers leaked one buffer per
// call. gen_ret now consults `__last_call_ret_owned__` for a direct
// parenthesised-call return, so ownership flows through call chains.
//
// Also locks the phi-escape ownership COPY: a ternary / match arm
// whose value is a bare load of an owned binding hands the phi
// consumer a strdup of the buffer, emitted inside that arm. The old
// protocol cancelled the binding's scheduled drop instead — but the
// cancel ran at the arm's symtab depth, so the pop resurrected the
// registration (double-free), and a phi consumer that outlived the
// binding's scope read freed memory. Under the copy contract the
// source binding STAYS VALID after the join, both the source and the
// phi result are auto-dropped exactly once, and no manual free is
// needed (one would now be a double-free).
//
// Frees are observable under ASan/LSan (run_san_tests.sh); this
// golden locks compile + run + output.

$ `stdlib/core/string.nu`

// Directly-returned fresh string — now marked __ret_owned=str.
@ mk_one → s {
    ^ ( nurl_str_cat `alpha-` `beta` )
}

// Two-level chain: ownership propagates transitively.
@ mk_two → s {
    ^ ( mk_one )
}

// Returned via binding (the previously-working shape — must keep working).
@ mk_bound → s {
    : s t ( nurl_str_cat `gamma-` `delta` )
    ^ t
}

@ main → i {
    : s a ( mk_one )
    ( nurl_print a ) ( nurl_print `\n` )

    : s b ( mk_two )
    ( nurl_print b ) ( nurl_print `\n` )

    : s c ( mk_bound )
    ( nurl_print c ) ( nurl_print `\n` )

    // Ternary phi-escape: the taken arm's value is the owned binding
    // `a`, so the phi receives a COPY and `sel` (both arms owned) is
    // auto-dropped. `a` stays valid and is auto-dropped too — reading
    // it again below locks that the arm did not consume it, and the
    // ABSENCE of any manual free locks single ownership: adding one
    // would double-free under the sanitizer run.
    : s sel ? 1 a ( mk_one )
    ( nurl_print sel ) ( nurl_print `\n` )
    ( nurl_print a ) ( nurl_print `\n` )

    // Match phi-escape: same contract through a `??` value arm.
    : ?i opt @ ?i { T 3 }
    : s msel ?? opt {
        T v → b
        F → ( mk_one )
    }
    ( nurl_print msel ) ( nurl_print `\n` )
    ( nurl_print b ) ( nurl_print `\n` )

    ( nurl_print `done\n` )
    ^ 0
}
