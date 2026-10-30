// H953: agora #206 — the same `^ cb` inside a `~` loop body (ret_param_loop_body_escape).
// Closed: bck_record_ret_param / bck_record_ret_alias write the function's own record (set_deep, as __record_param_idx does): a `^ p` inside a block, a loop or a `??` arm is summarised, so a call handing back a parameter there carries its referent depth (docs/MEMORY.md §2.8; agora #206).
// main: accepted; AddressSanitizer reported stack-use-after-scope.
: Counter { i n i max }

@ pick i k ( @ v ) cb → ( @ v ) {
    : ~ i j 0
    ~ < j k {
        ? == j 2 { ^ cb } {}
        = j + j 1
    }
    ^ \ → v {}
}

@ make → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( pick 5 f )
}

@ main → i {
    : ( @ v ) g ( make )
    ( g )
    ^ 0
}
