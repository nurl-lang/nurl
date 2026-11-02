// closure_clearing_a_field_of_its_parameter_ends_an_element_borrow: a closure that clears a Vec field of its struct parameter, called beside a borrow of an element.
// Closed: a closure literal is summarised from its own body as a function is (what it changes, moves or drops of its parameters, and the views it leaves between them), under its emitted name; a call through a binding that holds it is a call of the binding's summary node — the union of every literal and node bound to it — and a closure parameter's node is the union of what every caller passes there (agora #359, #403).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #359: a closure that clears a Vec field of its struct parameter, called beside a borrow of an element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Box { ( Vec String ) items }

@ main → i {
    : Box bx @ Box { ( vec_new [String] ) }
    ( vec_push [String] . bx items ( string_from `an element string long enough for a heap buffer` ) )
    : ( @ v Box ) clr \ Box b → v { ( vec_clear [String] . b items ) }
    : String s0 ( vec_at [String] . bx items 0 )
    ( clr bx )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
