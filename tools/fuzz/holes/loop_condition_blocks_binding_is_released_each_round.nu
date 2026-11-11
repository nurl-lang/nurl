// loop_condition_blocks_binding_is_released_each_round: `~ < { : String s …  : ( @ i i ) c \ … s …  ( c 0 ) } n { … }`.
// Closed: what a loop's condition binds is released where the round's condition has its value, before the branch on it (__loop_cond_release): the condition runs once per round, and the scope around it is the function's (agora #674, #628).
// main 6028243: accepted; a value block in a loop's condition binds in the function's scope, so its String and its closure's environment were released once, at the function's exit, and every round's but the last were never released (LeakSanitizer).
// map: §7.1 | A2 | runs-clean | - | agora #674: a String and a closure bound in a loop condition's value block leaked every round but the last
$ `stdlib/core/string.nu`

@ run String tag i n → i {
    : ~ i k 0
    ~ < { : String s ( string_concat tag tag ) : ( @ i i ) c \ i x → i { ^ + + x k ( string_len s ) } - ( c 0 ) ( string_len s ) } n { = k + k 1 }
    ^ k
}

@ main → i {
    : String t ( string_from `a tag long enough for a heap buffer, yes indeed` )
    ( nurl_println_int ( run t 4 ) )
    ^ 0
}
