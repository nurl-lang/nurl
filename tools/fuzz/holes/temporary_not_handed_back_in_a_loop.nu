// temporary_not_handed_back_in_a_loop: agora #457 — a temporary handed back on even iterations, a fresh value on odd ones
// Closed: a temporary argument the callee may hand back whole is dropped after the call on the runs whose per-call answer says the result is the callee's own (it was not handed back); on the runs it lends, it is the result (agora #457).
// main: LeakSanitizer reported the temporary (base a2f0fdf7).
// map: §7.2 | A2 | runs-clean | - | agora #457: a temporary handed back on even iterations, a fresh value on odd ones
$ `stdlib/core/string.nu`

@ maybe String a i k → String { ? == k 0 { ^ a } {} ^ ( string_from `a fresh value long enough for the heap here` ) }

@ main → i {
    : ~ i j 0
    : ~ i n 0
    ~ < j 6 {
        : String x ( maybe ( string_from `a temporary long enough for the heap` ) % j 2 )
        = n + n ( string_len x )
        = j + j 1
    }
    ( nurl_println_int n )
    ^ 0
}
