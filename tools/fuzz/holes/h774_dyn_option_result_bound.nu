// H774: agora #185 — the same with an option result (dyn_option_result_bound).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part String p b c → ?String { ^ @ ?String { T ? c p ( mk ) } }

@ main → i {
    : String p ( mk )
    : ?String t ( part p T )
    : ?String u ( part p F )
    ( nurl_println_int + + ?? t { T s → ( string_len s ) F → 0 } ?? u { T s → ( string_len s ) F → 0 } ( string_len p ) )
    ^ 0
}
