// owned_option_bound: agora #185 — an owned option result bound by `:` (owned_option_bound).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: ran clean (kept so it stays clean).
// map: §7.6 | A2 | runs-clean | h779 | agora #185: an owned option result bound by `:`
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ mko → ?String { ^ @ ?String { T ( mk ) } }

@ main → i {
    : ?String w ( mko )
    ( nurl_println_int ?? w { T s → ( string_len s ) F → 0 } )
    ^ 0
}
