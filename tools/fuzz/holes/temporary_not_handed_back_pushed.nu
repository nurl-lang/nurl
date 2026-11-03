// temporary_not_handed_back_pushed: agora #457 — the result pushed into a Vec; a Vec temporary the callee may hand back
// Closed: a temporary argument the callee may hand back whole is dropped after the call on the runs whose per-call answer says the result is the callee's own (it was not handed back); on the runs it lends, it is the result (agora #457).
// main: LeakSanitizer reported the temporary (base a2f0fdf7).
// map: §7.2 | A2 | runs-clean | - | agora #457: the result pushed into a Vec; a Vec temporary the callee may hand back
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ mv ( Vec i ) a i k → ( Vec i ) { ? == k 0 { ^ a } {} : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ v }

@ main → i {
    : ~ ( Vec String ) out ( vec_new [String] )
    ( vec_push [String] out ( maybe ( string_from `a temporary long enough for the heap` ) 1 ) )
    ( vec_push [String] out ( maybe ( string_from `a temporary long enough for the heap` ) 0 ) )
    : ( Vec i ) w ( mv ( vec_new [i] ) 1 )
    : ( Vec i ) w2 ( mv ( vec_new [i] ) 0 )
    ( nurl_println_int + + ( vec_len [String] out ) ( vec_len [i] w ) ( vec_len [i] w2 ) )
    ^ 0
}
