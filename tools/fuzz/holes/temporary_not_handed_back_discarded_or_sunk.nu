// temporary_not_handed_back_discarded_or_sunk: agora #457 — the result discarded, or handed to a `sink`
// Closed: a temporary argument the callee may hand back whole is dropped after the call on the runs whose per-call answer says the result is the callee's own (it was not handed back); on the runs it lends, it is the result (agora #457).
// main: LeakSanitizer reported the temporary (base a2f0fdf7).
// map: §7.2 | A2 | runs-clean | - | agora #457: the result discarded, or handed to a `sink`
$ `stdlib/core/string.nu`

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ eat sink String s → i { ^ ( string_len s ) }

@ main → i {
    ( maybe ( string_from `a temporary long enough for the heap` ) 1 )
    ( maybe ( string_from `a temporary long enough for the heap` ) 0 )
    ( nurl_println_int ( eat ( maybe ( string_from `a temporary long enough for the heap` ) 1 ) ) )
    ( nurl_println_int ( eat ( maybe ( string_from `a temporary long enough for the heap` ) 0 ) ) )
    ^ 0
}
