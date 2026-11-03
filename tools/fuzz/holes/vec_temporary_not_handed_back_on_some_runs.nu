// vec_temporary_not_handed_back_on_some_runs: agora #457 — the same with a Vec temporary
// Closed: a temporary argument the callee may hand back whole is dropped after the call on the runs whose per-call answer says the result is the callee's own (it was not handed back); on the runs it lends, it is the result (agora #457).
// main: LeakSanitizer reported the temporary (base a2f0fdf7).
// map: §7.2 | A2 | runs-clean | - | agora #457: the same with a Vec temporary
$ `stdlib/core/vec.nu`
$ `stdlib/core/io.nu`

@ mkv i n → ( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v n ) ^ v }

@ maybe ( Vec i ) a i k → ( Vec i ) { ? == k 0 { ^ a } {} ^ ( mkv 9 ) }

@ main → i {
    : ( Vec i ) x ( maybe ( mkv 4 ) 1 )
    ( nurl_println_int ( vec_len [i] x ) )
    ^ 0
}
