// dyn_result_in_struct_literal: agora #185 — a String result lent on one path, fresh on the other, as a struct literal's field (dyn_result_in_struct_literal).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h784 | agora #185: a String result lent on one path, fresh on the other, as a struct literal's field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String s i n }

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick String p b c → String { ^ ? c p ( mk ) }

@ main → i {
    : String p ( mk )
    : P a @ P { ( pick p T ) 1 }
    : P b @ P { ( pick p F ) 2 }
    ( nurl_println_int + + ( string_len . a s ) ( string_len . b s ) ( string_len p ) )
    ^ 0
}
