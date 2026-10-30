// dyn_option_result_in_a_loop: agora #185 — the option case in a loop (dyn_option_result_in_a_loop).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h777 | agora #185: the option case in a loop
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ part String p b c → ?String { ^ @ ?String { T ? c p ( mk ) } }

@ main → i {
    : String p ( mk )
    : ~ i k 0
    : ~ i acc 0
    ~ < k 10 {
        : ?String u ( part p > k 4 )
        = acc + acc ?? u { T s → ( string_len s ) F → 0 }
        = k + k 1
    }
    ( nurl_println_int acc )
    ^ 0
}
