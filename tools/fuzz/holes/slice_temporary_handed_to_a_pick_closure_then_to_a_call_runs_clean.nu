// slice_temporary_handed_to_a_pick_closure_then_to_a_call_runs_clean: `( ln ( f ( mk ) T ) )`: a pick-shaped closure's result handed straight on, and the same over a named slice
// Closed (agora #894): a call through a closure value whose result is an owned slice of elements that hold no view hands its caller a slice of its own on every run, the closure's where it said so at its return, else a copy (mem_clo_ret_copies_slc); a slice a call made, handed to it, goes after the call.
// main 977a74c: LeakSanitizer reported three slices never released.
// map: §7.6 | A2 | runs-clean | - | agora #894: ( ln ( f ( mk ) T ) ): a pick-shaped closure's result handed straight on, and the same over a named slice
@ mk → [i { ^ [i | 7 8 9] }
@ ln [i a → i { ^ . a 1 }

@ main → i {
    : ( @ [i [i b ) f \ [i a b c → [i { ? c { ^ a } {} ^ [i | 1 2 3] }
    : ( @ [i [i ) g \ [i a → [i { ^ a }
    ( nurl_println_int ( ln ( g ( mk ) ) ) )
    ( nurl_println_int ( ln ( f ( mk ) T ) ) )
    ( nurl_println_int ( ln ( f ( mk ) F ) ) )
    : [i t ( mk )
    ( nurl_println_int ( ln ( f t T ) ) )
    ( nurl_println_int ( ln ( f t F ) ) )
    ( nurl_println_int . t 1 )
    ^ 0
}
