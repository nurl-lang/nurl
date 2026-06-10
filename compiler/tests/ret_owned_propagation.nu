// Test: owned-string return propagation through `^ ( call )` (critic.md
// A4 follow-on). `__fn_ret_str_owned__` was only set when the return
// expression was a bare identifier already in `__owned_strings__`;
// a helper returning `^ ( nurl_str_cat … )` directly was never marked
// `__ret_owned=str`, so `: s x ( helper )` at the caller never
// registered a drop — composing string helpers leaked one buffer per
// call. gen_ret now consults `__last_call_ret_owned__` for a direct
// parenthesised-call return, so ownership flows through call chains.
//
// Also locks the phi-escape ownership transfer that the propagation
// surfaced (it bit the compiler's own gen_cast): a ternary / match
// arm whose value is a bare load of an owned binding hands the buffer
// to the phi consumer — the binding's scheduled drop is cancelled
// (conservative: worst case a leak, never a use-after-free), so the
// phi value stays readable after the owned binding's scope exits.
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

    // Ternary phi-escape: `sel` aliases `a` on the taken path. `a`'s
    // drop is cancelled at the phi and `sel` itself is untracked, so
    // the buffer is freed manually below — which doubles as the
    // single-ownership lock: were a's drop NOT cancelled, this free
    // would be a double-free under the sanitizer run.
    : s sel ? 1 a ( mk_one )
    ( nurl_print sel ) ( nurl_print `\n` )
    ( nurl_free sel )

    // Match phi-escape: same contract through a `??` value arm.
    : ?i opt @ ?i { T 3 }
    : s msel ?? opt {
        T v → b
        F → ( mk_one )
    }
    ( nurl_print msel ) ( nurl_print `\n` )
    ( nurl_free msel )

    ( nurl_print `done\n` )
    ^ 0
}
