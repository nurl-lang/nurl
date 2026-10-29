// H781: agora #185 — a String result of that kind passed straight to a call (dyn_result_as_argument).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick String p b c → String { ^ ? c p ( mk ) }

@ main → i {
    : String p ( mk )
    ( nurl_println_int + ( string_len ( pick p F ) ) ( string_len ( pick p T ) ) )
    ^ 0
}
