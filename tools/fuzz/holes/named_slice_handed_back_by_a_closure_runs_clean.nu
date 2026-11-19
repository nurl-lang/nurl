// named_slice_handed_back_by_a_closure_runs_clean: `: [i x ( f y )` with `f` handing back its parameter: `x` is a slice of its own, `y` stays the owner
// Closed (agora #894): the result is a copy where the closure lent its argument, and the argument stays its owner's (mem_clo_ret_copies_slc): the shape the fix must keep.
// main 977a74c: accepted, runs clean (the shape the fix must keep).
// map: §7.6 | A2 | runs-clean | - | agora #894: : [i x ( f y ) with f handing back its parameter: x is a slice of its own, y stays the owner
@ mk → [i { ^ [i | 7 8 9] }

@ main → i {
    : ( @ [i [i ) f \ [i a → [i { ^ a }
    : [i y ( mk )
    : [i x ( f y )
    ( nurl_println_int . x 1 )
    ( nurl_println_int . y 1 )
    ^ 0
}
