// callee_clears_a_field_of_its_params_element: a callee binds a struct element of its parameter and clears its Vec field, while the caller reads a String inside that field.
// Closed: a function clearing its parameter's element, through a local read out of it, directly, or through a field of one, drops the parameter's elements in its summary (agora #443, #447; #333 is their drop half of #315).
// main's compiler before #443/#447: compiled; ASan reported heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #333: a callee binds a struct element of its parameter and clears its Vec field, while the caller reads a String inside that field
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Box2 { ( Vec String ) items }

@ clr_el ( Vec Box2 ) p → v {
    : Box2 b ( vec_at [Box2] p 0 )
    ( vec_clear [String] . b items )
}

@ main → i {
    : ( Vec Box2 ) vv ( vec_new [Box2] )
    : ( Vec String ) its ( vec_new [String] )
    ( vec_push [String] its ( string_from `an element string long enough for a heap buffer` ) )
    ( vec_push [Box2] vv @ Box2 { its } )
    : String s0 ( vec_at [String] . ( vec_at [Box2] vv 0 ) items 0 )
    ( clr_el vv )
    ( nurl_println_int ( string_len s0 ) )
    ^ 0
}
