// static_lend_option_bound: agora #185 — a vec_get option, a lend on every path, bound by `:` (static_lend_option_bound).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: ran clean (kept so it stays clean).
// map: §7.6 | A2 | runs-clean | h778 | agora #185: a vec_get option, a lend on every path, bound by `:`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( mk ) )
    : ?String e ( vec_get [String] v 0 )
    ( nurl_println_int ?? e { T s → ( string_len s ) F → 0 } )
    ^ 0
}
