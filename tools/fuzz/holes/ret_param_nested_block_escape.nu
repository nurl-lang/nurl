// ret_param_nested_block_escape: agora #206 — `? c { ^ cb } {}` hands back a closure capturing `make`'s local by pointer (ret_param_nested_block_escape).
// Closed: bck_record_ret_param / bck_record_ret_alias write the function's own record (set_deep, as __record_param_idx does): a `^ p` inside a block, a loop or a `??` arm is summarised, so a call handing back a parameter there carries its referent depth (docs/MEMORY.md §2.8; agora #206).
// main: accepted; AddressSanitizer reported stack-use-after-scope.
// map: §2.8 | A2 | rejected | h952 | agora #206: a callee's `^ cb` inside a block was never summarised: a closure capturing a local by pointer escaped its frame
: Counter { i n i max }

@ pick b c ( @ v ) cb → ( @ v ) {
    ? c { ^ cb } {}
    ^ \ → v {}
}

@ make → ( @ v ) {
    : ~ Counter c @ Counter { 0 10 }
    : ( @ v ) f \ → v { = . c n + . c n 1 }
    ^ ( pick T f )
}

@ main → i {
    : ( @ v ) g ( make )
    ( g )
    ^ 0
}
