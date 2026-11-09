// loop_struct_element_field_read_after_its_containers_owner_is_cleared: agora #482 — `~ p b` over `b = ( vec_at vv 0 )`, a row of structs; `vv` cleared in the body; a field of `p` read after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop's struct element's field read after its container's owner is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { String name i n }

@ main → i {
    : ( Vec ( Vec P ) ) vv ( vec_new [( Vec P )] )
    : ~ ( Vec P ) t ( vec_new [P] )
    ( vec_push [P] t @ P { ( string_from `a name long enough for a heap buffer here` ) 1 } )
    ( vec_push [( Vec P )] vv t )
    : ( Vec P ) b ( vec_at [( Vec P )] vv 0 )
    ~ p b {
        ( vec_clear [( Vec P )] vv )
        ( nurl_println ( string_data . p name ) )
    }
    ^ 0
}
