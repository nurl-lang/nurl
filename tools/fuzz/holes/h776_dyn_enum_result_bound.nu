// H776: agora #185 — the same with an enum result (dyn_enum_result_bound).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

: | E {
    S String
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick E e b c → E { ^ ? c e @ E { S ( mk ) } }

@ main → i {
    : E g @ E { S ( mk ) }
    : E r ( pick g F )
    : E q ( pick g T )
    ( nurl_println_int + ?? r { S s → ( string_len s ) NoVal → 0 } ?? q { S s → ( string_len s ) NoVal → 0 } )
    ^ 0
}
