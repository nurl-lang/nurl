// returned_value_block_whose_tail_is_a_cursor_of_a_drop_element: `^ { … : D t ( vec_at [D] u 0 ) t }`, `u` the block's own Vec of a `% Drop` type.
// Closed: a returned value block whose tail is a binding hands it back as `^ t` does, and `^ t` refuses a cursor of a value that cannot be copied out of what the function drops on the way out. Handed back as the block stood, the element's destructor ran inside the function and the caller was given the dropped value (agora #649).
// main 6890060: accepted; the destructor runs before the caller reads the value (heap-use-after-free when it reads the String field).
// map: §2.2 | A2 | rejected | - | agora #649: a value block returned straight whose tail binding is a cursor of a `% Drop` element of another block binding
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: D {
    String s
    i n
}

% Drop D {
    @ drop D d → v { ( nurl_println_int . d n ) }
}

@ f i c → D {
    ^ { : ~ ( Vec D ) u ( vec_new [D] ) ( vec_push [D] u @ D { ( string_from `an element string long enough for the heap` ) c } ) : D t ( vec_at [D] u 0 ) t }
}

@ main → i {
    : D a ( f 1 )
    ( nurl_println ( string_data . a s ) )
    ^ 0
}
