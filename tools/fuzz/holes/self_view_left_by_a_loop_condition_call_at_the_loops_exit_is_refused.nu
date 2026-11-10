// self_view_left_by_a_loop_condition_call_at_the_loops_exit_is_refused: `~ ( hb p n ) { = p … }`: the loop's body gives p a new value, but the condition runs once more before the loop is left, then `. p s` grown
// Closed: a call's `sK` rows go after its own effects and before every other call's in the statement; a condition, a loop's exit and a return walk them; a closure's capture or parameter left viewing itself is refused, a panic path's view included (agora #584).
// main 4e090402: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: `~ ( hb p n ) { = p … }`: the loop's body gives p a new value, but the condition runs once more before the loop is left, then `. p s` grown
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ hb inout P p i n → b { = . p w @ W { ( string_data . p s ) } ^ < n 2 }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    : ~ i n 0
    ~ ( hb p n ) {
        = p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
        = n + n 1
    }
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
