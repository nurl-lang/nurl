// string_slice_temporary_handed_back_by_a_closure_runs_clean: `: [String x ( f ( mks ) )` with `f` = `\ [String a → [String { ^ a }`: the slice and its Strings are released
// Closed (agora #894): a call through a closure value whose result is an owned slice of elements that hold no view hands its caller a slice of its own on every run, the closure's where it said so at its return, else a copy (mem_clo_ret_copies_slc); a slice a call made, handed to it, goes after the call.
// main 977a74c: LeakSanitizer reported the slice and both Strings never released.
// map: §7.6 | A2 | runs-clean | - | agora #894: : [String x ( f ( mks ) ) with f = \ [String a → [String { ^ a }: the slice and its Strings are released
$ `stdlib/core/string.nu`

@ mks → [String { ^ [String | ( string_from `a` ) ( string_from `bc` )] }

@ main → i {
    : ( @ [String [String ) f \ [String a → [String { ^ a }
    : [String x ( f ( mks ) )
    ( nurl_println_int . x 1 )
    ^ 0
}
