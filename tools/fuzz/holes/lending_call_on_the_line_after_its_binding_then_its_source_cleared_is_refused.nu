// lending_call_on_the_line_after_its_binding_then_its_source_cleared_is_refused: `: S e` / `( first a )`, `first` handing back an element of its parameter, then `( vec_clear [S] a )` and `. e name` read
// Closed: a pending lend is keyed by its statement's line (agora #678).
// main 0b3f239a: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #678: a binding whose lending call is on the next line borrows from the call's argument
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: S { String name i n }

@ first ( Vec S ) a → S { ^ ( vec_at [S] a 0 ) }

@ main → i {
    : ( Vec S ) a ( vec_new [S] )
    ( vec_push [S] a @ S { ( string_from `a-long-enough-name-to-live-on-the-heap-000` ) 1 } )
    : S e
    ( first a )
    ( vec_clear [S] a )
    ( nurl_print ( string_data . e name ) )
    ^ 0
}
