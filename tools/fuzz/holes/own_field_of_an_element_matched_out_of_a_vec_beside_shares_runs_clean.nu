// own_field_of_an_element_matched_out_of_a_vec_beside_shares_runs_clean: `?? ( vec_get items 0 ) { T it → … }` and a slice of `. it own` kept past `( wipe r )` (the shape the fix must keep)
// Closed: a view's binding is marked with the Rc payloads its value is read through (`rcp_`: `rc_get` in its source expression, the bindings it names, a callee's answer g_fn_rcp); a call that may change one through another handle ends those views of a source that holds the Rc only in its elements' storage (agora #726).
// main 3b63ee3b: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #726: an element's own field matched out of a Vec beside shares, viewed past a reset
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
    ?? ( vec_get [Item] items 0 ) {
        T it → { : ( Slice u ) os ( slice_from_vec [u] . it own ) ( wipe r ) ( nurl_println_int # i ( slice_at [u] os 0 ) ) }
        F _ → {}
    }
    ^ 0
}
