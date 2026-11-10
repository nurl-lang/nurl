// self_view_left_by_a_panic_before_the_callees_repoint_is_refused: h makes the self-view, panics, and only then would give p a new value; a `recover` closure calls it through a wrapper, then `. p s` grown
// Closed: a call's `sK` rows go after its own effects and before every other call's in the statement; a condition, a loop's exit and a return walk them; a closure's capture or parameter left viewing itself is refused, a panic path's view included (agora #584).
// main 4e090402: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #584: h makes the self-view, panics, and only then would give p a new value; a `recover` closure calls it through a wrapper, then `. p s` grown
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: W { s v }
: P { W w String s String t }

$ `stdlib/std/panic.nu`

@ h inout P p → v {
    = . p w @ W { ( string_data . p s ) }
    ( panic `boom` )
    = p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
}

@ k inout P p → v { ( h p ) }

@ main → i {
    : ~ P p @ P { @ W { `x` } ( string_from `the first heap string, long enough to be on the heap for sure` ) ( string_from `the first heap string, long enough to be on the heap for sure` ) }
    : !v PanicInfo r ( recover \ → v { ( k p ) } )
    ?? r { T _ → {} F e → { ( panic_info_free e ) } }
    ( string_push_str . p s `and a long tail that makes the buffer move to a new place in memory for sure, really really for sure` )
    ( nurl_println . . p w v )
    ^ 0
}
