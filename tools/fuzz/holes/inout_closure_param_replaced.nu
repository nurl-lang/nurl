// inout_closure_param_replaced: a closure binding handed to an `inout` parameter that the callee assigns a new closure: the callee took the parameter for a local of its own — the new env was dropped when it returned and the old one leaked — so the caller's binding ran a freed env (heap-use-after-free).
// Closed: a closure binding reached through a pointer is a place that owns its env, as a struct field is (§7.4): the callee stores an owned value and releases the env it replaces; the caller first copies an env its binding only borrows, and its owner slot is a flag, the env dropped being the value's own (mem_clo_slot_env).
// main (before this PR): AddressSanitizer reported heap-use-after-free calling the replaced closure.
// map: StmtT.assign | A2 | runs-clean | h297 | a closure handed to an inout parameter and replaced there: the callee dropped the new env as its own and leaked the old; the caller ran freed memory
@ swap inout ( @ i i ) g i k → v { = g \ i x → i { ^ * x k } }

@ main → i {
    : i base 7
    : ~ ( @ i i ) f \ i x → i { ^ + x base }
    ( swap f 3 )
    ( nurl_println_int ( f 5 ) )
    ^ 0
}
