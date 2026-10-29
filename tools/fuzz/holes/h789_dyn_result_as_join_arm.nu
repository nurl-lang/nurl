// H789: agora #185 — the same result as an arm of a `?` bound by `:`, in a loop (dyn_result_as_join_arm).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick String p b c → String { ^ ? c p ( mk ) }

@ pick_opt String p b c → ?String { ^ @ ?String { T ? c p ( mk ) } }

@ main → i {
    : String p ( mk )
    : ~ i acc 0
    : ~ i k 0
    ~ < k 4 {
        : String t ? > k 1 ( pick p > k 2 ) ( mk )
        = acc + acc ( string_len t )
        = k + k 1
    }
    ( nurl_println_int + acc ( string_len p ) )
    ^ 0
}
