// ret_param_match_arm_escape: agora #206 — the same `^ cb` inside a `??` arm (ret_param_match_arm_escape).
// Closed: bck_record_ret_param / bck_record_ret_alias write the function's own record (set_deep, as __record_param_idx does): a `^ p` inside a block, a loop or a `??` arm is summarised, so a call handing back a parameter there carries its referent depth (docs/MEMORY.md §2.8; agora #206).
// main: accepted; AddressSanitizer reported stack-use-after-scope.
// map: §2.8 | A2 | rejected | h954 | the same `^ cb` inside a `??` arm
: Counter { i n i max }

@ pick ? i o ( @ v ) cb → ( @ v ) {
    ?? o { T x → { ^ cb } F → {} }
    ^ \ → v {}
}

@ make → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( pick @ ?i { T 1 } f )
}

@ main → i {
    : ( @ v ) g ( make )
    ( g )
    ^ 0
}
