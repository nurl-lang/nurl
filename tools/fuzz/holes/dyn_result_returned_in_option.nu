// dyn_result_returned_in_option: agora #185 — the same result as a returned option literal's payload (dyn_result_returned_in_option).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h786 | agora #185: the same result as a returned option literal's payload
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick String p b c → String { ^ ? c p ( mk ) }

@ wrap String p b c → ?String { ^ @ ?String { T ( pick p c ) } }

@ main → i {
    : String p ( mk )
    : ?String a ( wrap p T )
    : ?String b ( wrap p F )
    ( nurl_println_int + + ?? a { T s → ( string_len s ) F → 0 } ?? b { T s → ( string_len s ) F → 0 } ( string_len p ) )
    ^ 0
}
