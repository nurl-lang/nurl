// slice_temporary_handed_to_a_pick_closure_bound_runs_clean: `: [i x ( f ( mk ) T )` with `f` handing back its parameter on some runs and a fresh slice on others
// Closed (agora #894): a call through a closure value whose result is an owned slice of elements that hold no view hands its caller a slice of its own on every run, the closure's where it said so at its return, else a copy (mem_clo_ret_copies_slc); a slice a call made, handed to it, goes after the call.
// main 977a74c: LeakSanitizer reported two slices never released.
// map: §7.6 | A2 | runs-clean | - | agora #894: : [i x ( f ( mk ) T ) with f handing back its parameter on some runs and a fresh slice on others
@ mk → [i { ^ [i | 7 8 9] }

@ main → i {
    : ( @ [i [i b ) f \ [i a b c → [i { ? c { ^ a } {} ^ [i | 1 2 3] }
    : [i x ( f ( mk ) T )
    : [i y ( f ( mk ) F )
    ( nurl_println_int . x 1 )
    ( nurl_println_int . y 1 )
    ^ 0
}
