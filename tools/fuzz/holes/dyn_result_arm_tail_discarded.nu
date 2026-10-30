// dyn_result_arm_tail_discarded: agora #185 — the same result as an arm's discarded tail, in a loop (dyn_result_arm_tail_discarded).
// Closed: a call's result that the callee answers per call (a lend of its argument on some paths, fresh on others) goes by that answer wherever it lands — a binding, an argument's temporary, a discarded value, a store, a join's arm, a match's scrutinee — also when the callee hands back a view of its argument (__call_answers; agora #185).
// main: accepted; LeakSanitizer.
// map: §7.6 | A2 | runs-clean | h783 | agora #185: the same result as an arm's discarded tail, in a loop
$ `stdlib/core/string.nu`

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ pick String p b c → String { ^ ? c p ( mk ) }

@ main → i {
    : String p ( mk )
    : ~ i k 0
    ~ < k 3 {
        ? > k 0 { ( pick p F ) } {}
        = k + k 1
    }
    ( nurl_println_int ( string_len p ) )
    ^ 0
}
