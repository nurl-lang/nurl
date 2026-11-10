// self_view_left_by_a_call_then_the_field_grown_in_the_same_return_is_refused: `^ + ( h p ) ( g p )` in a function with `inout P p`: the field is grown after the self-view in the return's own expression
// Closed: a call's `sK` rows go after its own effects and before every other call's in the statement; a condition, a loop's exit and a return walk them; a closure's capture or parameter left viewing itself is refused, a panic path's view included (agora #584).
// main 4e090402: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: `^ + ( h p ) ( g p )` in a function with `inout P p`: the field is grown after the self-view in the return's own expression
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → i { = . p w @ W { ( string_data . p s ) } ^ 1 }

@ g inout P p → i { ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` ) ^ 1 }

@ rd P p → i { ( nurl_println . . p w v ) ^ 0 }

@ k inout P p → i { ^ + ( h p ) ( g p ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    : i z ( k p )
    ( nurl_println . . p w v )
    ^ z
}
