// struct_field_viewed_past_a_callee_growing_a_field_of_an_element_runs_clean: `: a ( vec_at . w apps 0 ) : nm . a name` grown in the callee, the caller keeping `( string_data . w title )`
// Kept: a callee that grows only what is inside an element of a container in its parameter (g_fn_ireallocs without g_fn_ifreallocs) leaves the caller's views of the argument's field paths' own buffers be (agora #647).
// main c5115caa: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #647: a struct field's view past a callee growing a field of an element
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: App { String name i n }
: W { ( Vec App ) apps String title }

@ ext W w → v {
    : App a ( vec_at [App] . w apps 0 )
    : String nm . a name
    ( string_push_str nm `, and a good deal more text so the buffer has to move somewhere else` )
}

@ main → i {
    : ( Vec App ) as ( vec_new [App] )
    ( vec_push [App] as @ App { ( string_from `a name long enough to live on the heap` ) 1 } )
    : W w @ W { as ( string_from `a title long enough to live on the heap too` ) }
    : s view ( string_data . w title )
    ( ext w )
    ( nurl_eprintln view )
    ^ 0
}
