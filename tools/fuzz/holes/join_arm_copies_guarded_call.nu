// join_arm_copies_guarded_call: a `?` value join whose arm is a call answering ownership per call (it lends its argument on some paths and hands a fresh string over on others) copied the arm when the last identifier loaded inside the call was a tracked owned string — that identifier is only the call's argument — and the result the call had handed over through its guard was never released: one leak per evaluation.
// Closed: when a call arm is copied, what the call handed over through its guard is freed right after the copy (gen_cond, both arms).
// main (before this PR): LeakSanitizer, one string per evaluation.
// map: §7.1 | A2 | runs-clean | h194 | ?-join copies a call arm that handed a fresh string over: string leaks
$ `stdlib/core/string.nu`

: ~ i g_n 0

@ fresh → s {
    = g_n + g_n 1
    ^ ( nurl_str_cat `r` ( nurl_str_int g_n ) )
}

@ key s ty s v → s {
    ? ( nurl_str_eq ty `p` ) { ^ v } {}
    ? ( nurl_str_eq ty `a` ) {
        : s r ( fresh )
        ^ r
    } {}
    ^ ( key `a` v )
}

@ pick s owners s ty → i {
    : s av ( fresh )
    : s k ? == 0 ( nurl_str_len owners ) ( nurl_str_cat `` `` ) ( key ty av )
    : s j ? != 0 ( nurl_str_len owners ) ( key ty av ) ( nurl_str_cat `` `` )
    ^ + ( nurl_str_len k ) ( nurl_str_len j )
}

@ main → i {
    : ~ i t 0
    = t + t ( pick `` `a` )
    = t + t ( pick `x` `a` )
    = t + t ( pick `x` `p` )
    = t + t ( pick `x` `z` )
    ( nurl_println_int t )
    ^ 0
}
