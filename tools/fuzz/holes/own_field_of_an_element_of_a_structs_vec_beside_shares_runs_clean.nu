// own_field_of_an_element_of_a_structs_vec_beside_shares_runs_clean: `: W { ( Vec Item ) items }`, a slice of `. ( vec_at . w items 0 ) own` kept past `( wipe r )` (the shape the fix must keep)
// Closed: a view's binding is marked with the Rc payloads its value is read through (`rcp_`: `rc_get` in its source expression, the bindings it names, a callee's answer g_fn_rcp); a call that may change one through another handle ends those views of a source that holds the Rc only in its elements' storage — its own buffer, its element handles and its elements' own fields stay (agora #726).
// main 1a44e524: runs clean.
// map: §2.10 | A2 | runs-clean | - | agora #726: an element's own field of a struct's Vec beside shares, viewed past a reset
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/hashmap.nu`

@ wipe ( Rc ( Vec u ) ) r → v { ( vec_clear [u] ( rc_get [( Vec u )] r ) ) ( vec_shrink_to_fit [u] ( rc_get [( Vec u )] r ) ) }

: Item { ( Rc ( Vec u ) ) sh ( Vec u ) own }
: W { ( Vec Item ) items i n }

@ main → i {
    : ( Vec u ) v0 ( vec_new [u] )
    ( vec_push [u] v0 7 )
    : ( Rc ( Vec u ) ) r ( rc_new [( Vec u )] v0 )
    : ~ ( Vec u ) data ( vec_new [u] )
    ( vec_push [u] data 42 )
    : ~ ( Vec Item ) items ( vec_new [Item] )
    ( vec_push [Item] items @ Item { ( rc_clone [( Vec u )] r ) data } )
    : W w @ W { items 1 }
    : ( Slice u ) os ( slice_from_vec [u] . ( vec_at [Item] . w items 0 ) own )
    ( wipe r )
    ( nurl_println_int # i ( slice_at [u] os 0 ) )
    ^ 0
}
