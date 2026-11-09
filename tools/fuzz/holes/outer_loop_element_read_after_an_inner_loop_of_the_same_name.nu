// outer_loop_element_read_after_an_inner_loop_of_the_same_name: agora #482 — `~ x a { ~ x b {} … }`: an inner loop of the same name; then the outer `x`'s container cleared through an alias, outer `x` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: an outer loop element read after an inner loop of the same name and a clear through an alias
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ( Vec String ) a ( vec_at [( Vec String )] vv 0 )
    : ( Vec String ) b ( vec_new [String] )
    ( vec_push [String] b ( string_from `another string long enough for a heap buffer` ) )
    ~ x a {
        ~ x b { ( nurl_println ( string_data x ) ) }
        ( vec_clear [( Vec String )] vv )
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
