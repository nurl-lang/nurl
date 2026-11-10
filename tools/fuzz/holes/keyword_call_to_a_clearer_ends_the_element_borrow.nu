// keyword_call_to_a_clearer_ends_the_element_borrow: `( clr v: v )`, a clearer called with its argument by name, while a vec_at binding of v is held and read after (formal d_43).
// Closed: a keyword call naming its arguments in declared order takes the positional path, borrow rows and all (agora #434).
// main 74a4a4eb: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #434: `( clr v: v )`, a clearer called with its argument by name, while a vec_at binding of v is held and read after (formal d_43)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ clr ( Vec String ) v → v { ( vec_clear [String] v ) }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string, long enough for the heap` ) )
    : String e ( vec_at [String] v 0 )
    ( clr v : v )
    ( nurl_println ( string_data e ) )
    ^ 0
}
