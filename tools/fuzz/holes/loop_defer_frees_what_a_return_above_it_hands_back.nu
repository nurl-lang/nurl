// loop_defer_frees_what_a_return_above_it_hands_back: `: String x …  ~ c { ? d { ^ x } {}  ; { ( string_free x ) } }`.
// Closed: rejected. A `^` above a loop body's `;` runs that defer from the second round on (an earlier round armed it, agora #670), after the value is the caller's: the defer frees what the caller gets, as one above the `^` would (agora #165).
// main 0b3f239: accepted; it ran clean only because the `^` skipped the defer (#670's wrong output). With the defer run there and the walk unchanged: AddressSanitizer: heap-use-after-free in the caller.
// map: §7.2 | A2 | rejected | - | agora #670: a `^` above a loop body's `;` hands back what that defer, armed in an earlier round, frees
$ `stdlib/core/string.nu`

@ f i d → String {
    : String x ( string_from `x: a string long enough for a heap buffer` )
    : ~ i k 0
    ~ < k 3 {
        ? == k d { ^ x } {}
        ; { ( string_free x ) }
        = k + k 1
    }
    ^ ( string_from `fell off the end of the function` )
}

@ main → i {
    : String a ( f 1 )
    ( nurl_println ( string_data a ) )
    ^ 0
}
