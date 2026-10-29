// H780: agora #185 — a struct result lent on one path, fresh on the other, bound by `:` (dyn_struct_result_bound).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick String p b c → String { ^ ? c p ( mk ) }

@ pickp P p b c → P { ^ ? c p @ P { ( mk ) 2 } }

@ main → i {
    : P p @ P { ( mk ) 1 }
    : P r ( pickp p F )
    : P q ( pickp p T )
    ( nurl_println_int + + ( string_len . r s ) ( string_len . q s ) ( string_len . p s ) )
    ^ 0
}
