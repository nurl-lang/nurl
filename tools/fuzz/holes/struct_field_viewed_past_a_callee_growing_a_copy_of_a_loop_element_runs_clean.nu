// struct_field_viewed_past_a_callee_growing_a_copy_of_a_loop_element_runs_clean: the callee copies a `~` loop element of a Vec field, `: ( Vec u ) rr r`, and grows the copy
// Kept: a handle that is an element's for certain — a copy of a `~` loop's element, a field of an element read inline — grown in the callee leaves the caller's views of the argument's field paths' own buffers be (agora #647).
// main c5115caa: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #647: a struct field's view past a callee growing a copy of a loop element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: W { ( Vec ( Vec u ) ) rows String name }

@ ext W p → v { ~ r . p rows { : ( Vec u ) rr r ( vec_reserve [u] rr 4096 ) } }

@ main → i {
    : ( Vec ( Vec u ) ) rs ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] rs ( vec_new [u] ) )
    : W w @ W { rs ( string_from `a name long enough to live on the heap` ) }
    : s view ( string_data . w name )
    ( ext w )
    ( nurl_eprintln view )
    ^ 0
}
