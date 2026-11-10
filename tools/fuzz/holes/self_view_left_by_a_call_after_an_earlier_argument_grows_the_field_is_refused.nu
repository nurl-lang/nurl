// self_view_left_by_a_call_after_an_earlier_argument_grows_the_field_is_refused: `( g2 . p s ( h p ) )`: the call that grows `. p s` was handed the field before the self-viewing call ran inside its own argument list
// Closed: a call's `sK` rows go after its own effects and before every other call's in the statement; a condition, a loop's exit and a return walk them; a closure's capture or parameter left viewing itself is refused, a panic path's view included (agora #584).
// main 4e090402: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: `( g2 . p s ( h p ) )`: the call that grows `. p s` was handed the field before the self-viewing call ran inside its own argument list
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → i { = . p w @ W { ( string_data . p s ) } ^ 1 }

@ g2 inout String s i x → i { ( string_push_str s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` ) ^ x }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    : i z ( g2 . p s ( h p ) )
    ( nurl_println . . p w v )
    ^ z
}
