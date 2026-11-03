// closure_called_with_an_element_a_call_lends_clears_it: a clearing closure called with `( vec_at outer 0 )` while a borrow of that element's element is held.
// Closed: a closure call keeps a lending argument's sources (pendlend rows against its node), whose summary closes at module end as a function's does (agora #421).
// main's compiler: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #421: a clearing closure called with `( vec_at outer 0 )` while a borrow of that element's element is held
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) outer ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] outer ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] outer 0 ) ( string_from `another element string long enough for a heap buffer` ) )
    : ( @ v ( Vec String ) ) f \ ( Vec String ) x → v { ( vec_clear [String] x ) }
    : String s0 ( vec_at [String] ( vec_at [( Vec String )] outer 0 ) 0 )
    ( f ( vec_at [( Vec String )] outer 0 ) )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
