// closure_hands_back_a_struct_of_a_view_and_an_owner_of_its_capture: a closure hands back a literal of a view of its capture beside an owned field.
// Closed: a closure may not hand back an owner that holds views of what it captured, as it may not hand back such a view (h220): its caller cannot see what the capture points into (agora #369).
// main 4d57d596: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | rejected | - | agora #369: a closure hands back a literal of a view of its capture beside an owned field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tok { s w String b }

@ show Tok t → v { ( nurl_println . t w ) }

@ main → i {
    : ( Vec Tok ) toks ( vec_new [Tok] )
    {
        : String line ( string_from `hello world, long enough for a heap buffer` )
        : ( @ Tok ) mk \ → Tok { ^ @ Tok { ( string_data line ) ( string_from `x` ) } }
        ( vec_push [Tok] toks ( mk ) )
    }
    ( show ( vec_at [Tok] toks 0 ) )
    ^ 0
}
