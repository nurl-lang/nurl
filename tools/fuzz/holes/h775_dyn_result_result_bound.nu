// H775: agora #185 — the same with a result type (dyn_result_result_bound).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part String p b c → !String i { ^ @ !String i { T ? c p ( mk ) } }

@ main → i {
    : String p ( mk )
    : !String i t ( part p T )
    : !String i u ( part p F )
    ( nurl_println_int + ?? t { T s → ( string_len s ) F e → e } ?? u { T s → ( string_len s ) F e → e } )
    ^ 0
}
