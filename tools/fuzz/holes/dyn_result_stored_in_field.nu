// dyn_result_stored_in_field: agora #185 — the same result stored into a field (dyn_result_stored_in_field).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h787 | agora #185: the same result stored into a field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick String p b c → String { ^ ? c p ( mk ) }

@ main → i {
    : String p ( mk )
    : ~ P a @ P { ( mk ) 1 }
    = . a s ( pick p T )
    = . a s ( pick p F )
    ( nurl_println_int + ( string_len . a s ) ( string_len p ) )
    ^ 0
}
