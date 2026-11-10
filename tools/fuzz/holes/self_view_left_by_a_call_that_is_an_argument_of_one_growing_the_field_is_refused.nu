// self_view_left_by_a_call_that_is_an_argument_of_one_growing_the_field_is_refused: `( g2 ( h p ) p )`: the self-view is made inside an argument of a call that then grows `. p s`, then the view is read
// Closed: a call's `sK` rows go after its own effects and before every other call's in the statement; a condition, a loop's exit and a return walk them; a closure's capture or parameter left viewing itself is refused, a panic path's view included (agora #584).
// main 4e090402: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: `( g2 ( h p ) p )`: the self-view is made inside an argument of a call that then grows `. p s`, then the view is read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { W w String s String t }

@ g2 i x inout P p → v { ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` ) }

@ h inout P p → i { = . p w @ W { ( string_data . p s ) } ^ 1 }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    : ~ P p2 @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ( g2 ( h p ) p )
    ( nurl_println . . p w v )
    ^ 0
}
