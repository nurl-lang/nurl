// own_field_of_an_element_beside_its_share_kept_past_a_reset_runs_clean: `: Item { ( Rc ( Vec u ) ) sh ( Vec u ) own }`, a slice of `. ( vec_at items 0 ) own` kept past `( wipe r )`: an element's own field is no payload (the shape the fix must keep)
// Closed: a view's binding is marked with the Rc payloads its value is read through (`rcp_`: `rc_get` in its source expression, the bindings it names, a callee's answer g_fn_rcp); a call that may change one through another handle ends those views of a source that holds the Rc only in its elements' storage (agora #726).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #726: an element's own field beside its share, viewed past a reset
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

: Item { ( Rc ( Vec u ) ) sh ( Vec u ) own }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ~ ( Vec u ) data ( vec_new [u] )
    ( vec_push [u] data 42 )
    : ~ ( Vec Item ) items ( vec_new [Item] )
    ( vec_push [Item] items @ Item { ( rc_clone [( Vec u )] r ) data } )
    : ( Slice u ) os ( slice_from_vec [u] . ( vec_at [Item] items 0 ) own )
    ( wipe r )
    ( nurl_println_int # i ( slice_at [u] os 0 ) )
    ^ 0
}
