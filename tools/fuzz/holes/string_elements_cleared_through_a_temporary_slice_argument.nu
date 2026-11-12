// string_elements_cleared_through_a_temporary_slice_argument: agora #735 — `( ch ( slice_from_vec [( Vec String )] vs ) )`, ch clearing `( slice_at ss 0 )`, beside a borrow of an element's String
// Closed: what a callee changes through a `~` loop element of its parameter is in its drop summary for that parameter (the loop's container, `__econt`, is a source of the element: __pderiv_reach); and a slice argument that is a call lending out of a binding — `( ch ( slice_from_vec vs ) )` — names that binding to the walk, as a handle argument does (agora #735, #737).
// main 3a71bef7: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #735: `( ch ( slice_from_vec [( Vec String )] vs ) )`, ch clearing `( slice_at ss 0 )`, beside a borrow of an element's String
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

@ ch ( Slice ( Vec String ) ) ss → v { ( vec_clear [String] ( slice_at [( Vec String )] ss 0 ) ) }

@ main → i {
    : ( Vec String ) a ( vec_new [String] )
    ( vec_push [String] a ( string_from `an element string long enough for a heap buffer` ) )
    : ( Vec ( Vec String ) ) vs ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] vs a )
    : String e ( vec_at [String] ( vec_at [( Vec String )] vs 0 ) 0 )
    ( ch ( slice_from_vec [( Vec String )] vs ) )
    ( nurl_println ( string_data e ) )
    ^ 0
}
