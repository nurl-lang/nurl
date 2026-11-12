// struct_field_viewed_past_a_callee_growing_a_loop_element_runs_clean: `~ r . p rows { ( vec_reserve r 4096 ) }` in the callee, the caller keeping `( string_data . w name )`
// Kept: a callee that grows only what is inside an element of a container in its parameter (g_fn_ireallocs without g_fn_ifreallocs) leaves the caller's views of the argument's field paths' own buffers be (agora #647).
// main c5115caa: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #647: a struct field's view past a callee growing loop elements of another field
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: W { ( Vec ( Vec u ) ) rows String name }

@ growrow W p → v { ~ r . p rows { ( vec_reserve [u] r 4096 ) } }

@ main → i {
    : ( Vec ( Vec u ) ) rs ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] rs ( vec_new [u] ) )
    : W w @ W { rs ( string_from `a name long enough to live on the heap` ) }
    : s view ( string_data . w name )
    ( growrow w )
    ( nurl_eprintln view )
    ^ 0
}
