// loop_closure_element_called_after_its_containers_owner_is_cleared: agora #482 — `~ f b` over `b = ( vec_at vv 0 )`, a row of closures; `vv` cleared in the body; `f` called after
// Closed: the loop's element is a copy of the handle in an element of what the loop iterates; what ends a borrow of an element of its owners ends it, by any route (`feo_`, agora #482).
// main 21a0fb5: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #482: a loop's closure element called after its container's owner is cleared
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : i k 42
    : ( Vec ( Vec ( @ i ) ) ) vv ( vec_new [( Vec ( @ i ) )] )
    : ~ ( Vec ( @ i ) ) t ( vec_new [( @ i )] )
    ( vec_push [( @ i )] t \ → i { ^ k } )
    ( vec_push [( Vec ( @ i ) )] vv t )
    : ( Vec ( @ i ) ) b ( vec_at [( Vec ( @ i ) )] vv 0 )
    ~ f b {
        ( vec_clear [( Vec ( @ i ) )] vv )
        ( nurl_println_int ( f ) )
    }
    ^ 0
}
