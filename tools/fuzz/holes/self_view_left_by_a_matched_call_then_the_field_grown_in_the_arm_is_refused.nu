// self_view_left_by_a_matched_call_then_the_field_grown_in_the_arm_is_refused: `?? ( h p ) { T x → { grow . p s ; read } F → {} }`
// Closed: a call's `sK` rows go after its own effects and before every other call's in the statement; a condition, a loop's exit and a return walk them; a closure's capture or parameter left viewing itself is refused, a panic path's view included (agora #584).
// main 4e090402: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: `?? ( h p ) { T x → { grow . p s ; read } F → {} }`
$ `stdlib/core/string.nu`

: W { s v }
: P { W w String s String t }

@ h inout P p → ?i { = . p w @ W { ( string_data . p s ) } ^ @ ?i { T 1 } }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    ?? ( h p ) { T x → { ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` ) ( nurl_println . . p w v ) } F → {} }
    ^ 0
}
