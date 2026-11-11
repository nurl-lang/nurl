// loop_defer_frees_what_a_return_above_it_hands_back: `: String x …  ~ c { ? d { ^ x } {}  ; { ( string_free x ) } }`.
// Closed: rejected. A defer further down a loop body than a `^` may run at that `^` (an earlier round armed it): the walk's ret row reads it for what it does to the owner handed back (bck_defers_release_ret, __bck_rows_share_loop), as it does a defer above the `^` (agora #655, #165).
// main ee9d2c5: accepted; it ran clean only because the `^` skipped the armed defer. With the defer run, the caller gets freed memory.
// map: §5.3 | A2 | rejected | - | agora #655: a loop body's `;` frees what a `^` above it hands back
$ `stdlib/core/string.nu`

@ f i n → String {
    : String x ( string_from `x: an outer string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 3 {
        ? == k n { ^ x } {}
        ; { ( string_free x ) }
        = k + k 1
    }
    ^ ( string_from `fell off` )
}

@ main → i {
    : String a ( f 1 )
    ( nurl_println ( string_data a ) )
    ^ 0
}
