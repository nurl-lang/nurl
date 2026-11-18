// fresh_slice_handed_back_through_a_lending_call_in_a_return_runs_clean: `^ ( id ( mk ) )` and `^ ( pick ( pick a fresh ) F )`: the returned slice is the caller's on the runs the inner call's was fresh
// Closed (agora #895, the `^` shape): a function returning a lending call's result over a slice temporary answers by the bit the call left - the temporary handed back whole is its own on those runs - and answers per call (gen_ret, __slice_call_own_bit, __hown_dyn).
// main 34edc2a1: LeakSanitizer reported the temporary slice never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-895: `^ ( id ( mk ) )`: the returned slice is the caller's on the runs the inner call's was fresh
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ mk → [i { ^ [i | 7 8 9] }
@ id [i a → [i { ^ a }
@ f → [i { ^ ( id ( mk ) ) }
@ pick [i a b fresh → [i { ? fresh { ^ [i | 7 8 9] } {} ^ a }
@ g [i a b fresh → [i { ^ ( pick ( pick a fresh ) F ) }
@ run b fresh → v {
    : [i a [i | 1 2]
    : [i x ( f )
    : [i y ( g a fresh )
    ( nurl_println_int . x 1 )
    ( nurl_println_int . y 1 )
}
@ main → i { ( run T ) ( run F ) ^ 0 }
