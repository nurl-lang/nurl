// inner_loop_element_read_after_the_outer_element_is_cleared_through_a_copy: agora #482 — `~ x vv { : ~ c x ~ y x { ( vec_clear c ) y read } }` — `y`'s slot is one of `x`'s elements
// Closed: a copy of the outer element shares its bytes, and dropping its elements ends the inner loop's element, which is one of them (agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: an inner loop element read after the outer element is cleared through a copy
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [( Vec String )] vv t )
    : ~ ( Vec String ) t2 ( vec_new [String] )
    ( vec_push [String] t2 ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [( Vec String )] vv t2 )
    ~ x vv {
        : ~ ( Vec String ) c x
        ~ y x {
            ( vec_clear [String] c )
            ( nurl_println ( string_data y ) )
            break
        }
    }
    ^ 0
}
