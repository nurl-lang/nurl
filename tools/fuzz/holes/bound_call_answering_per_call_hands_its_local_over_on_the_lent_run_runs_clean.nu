// bound_call_answering_per_call_hands_its_local_over_on_the_lent_run_runs_clean: `: String r ( maybe x k )  ^ r`, `maybe` handing `x` back on one path and a fresh String on the other, run on both
// AGORA-995's return handover for a bound call (`__bind_hand`): where the callee answers per call and the binding is bound straight from the call, its flag is the call's answer. On the run the call lent, `x` is handed over (no copy); on the other the result is fresh and `x` is dropped. Before, the bound form copied the String on the lent run (found by review of github#2280).
// main: runs clean (with a copy).
// map: §7.6 | A2 | runs-clean | - | AGORA-995: a bound per-call lend of a local is handed over on its lent run only
$ `stdlib/core/string.nu`

@ maybe String a i k → String {
    ? == k 0 { ^ a } {}
    ^ ( string_from `a fresh value long enough for the heap here` )
}

@ esc i k → String {
    : String x ( string_from `a local value long enough for the heap` )
    : String r ( maybe x k )
    ^ r
}

@ main → i {
    : String a ( esc 0 )
    : String b ( esc 1 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data b ) )
    ^ 0
}
