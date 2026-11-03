// callee_clears_an_element_of_its_param_through_a_local: a callee binds an element of its Vec-of-Vec parameter and clears it, while the caller reads a String inside that element through a bound element.
// Closed: a function clearing its parameter's element, through a local read out of it, directly, or through a field of one, drops the parameter's elements in its summary (agora #443, #447; #333 is their drop half of #315).
// main's compiler before #443/#447: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #333: a callee binds an element of its Vec-of-Vec parameter and clears it, while the caller reads a String inside that element through a bound element
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Box2 { ( Vec String ) items }

@ clr_el ( Vec ( Vec String ) ) p → v {
    : ( Vec String ) e ( vec_at [( Vec String )] p 0 )
    ( vec_clear [String] e )
}

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vv ( vec_new [String] ) )
    ( vec_push [String] ( vec_at [( Vec String )] vv 0 ) ( string_from `an element string long enough for a heap buffer` ) )
    : ( Vec String ) e0 ( vec_at [( Vec String )] vv 0 )
    : String s0 ( vec_at [String] e0 0 )
    ( clr_el vv )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
