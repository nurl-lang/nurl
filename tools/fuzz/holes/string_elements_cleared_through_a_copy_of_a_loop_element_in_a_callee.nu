// string_elements_cleared_through_a_copy_of_a_loop_element_in_a_callee: agora #735 — `~ x vs { : ( Vec String ) y x  ( vec_clear [String] y ) }` beside a borrow of an element's String
// Closed: a `~` loop element is noted, by its slot, as read out of the parameters its container was (__pderiv_note at gen_foreach); a closure's capture of it, and a binding copying it, are too; an option of a slice argument names its binding to the walk (agora #735).
// main 4dfee821: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #735: `~ x vs { : ( Vec String ) y x  ( vec_clear [String] y ) }` beside a borrow of an element's String
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/rc.nu`

$ `stdlib/core/box.nu`

@ mkvv s t → ( Vec ( Vec String ) ) {
    : ( Vec String ) a ( vec_new [String] )
    ( vec_push [String] a ( string_from t ) )
    : ( Vec ( Vec String ) ) vs ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vs a )
    ^ vs
}

@ ch ( Vec ( Vec String ) ) vs → v { ~ x vs { : ( Vec String ) y x ( vec_clear [String] y ) } }

@ main → i {
    : ( Vec ( Vec String ) ) vs ( mkvv `a string long enough to live on the heap for sure` )
    : String e ( vec_at [String] ( vec_at [( Vec String )] vs 0 ) 0 )
    ( ch vs )
    ( nurl_println ( string_data e ) )
    ^ 0
}
