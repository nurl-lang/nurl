// struct_fields_vec_looped_over_past_a_callee_growing_its_elements_runs_clean: a `~` loop over `. w rows` calling a callee that reserves `( vec_at . p rows 0 )`
// Kept: a callee that grows only what is inside an element of a container in its parameter (g_fn_ireallocs without g_fn_ifreallocs) leaves the caller's views of the argument's field paths' own buffers be (agora #647).
// main c5115caa: accepted; runs clean under AddressSanitizer.
// map: §2.10 | A2 | runs-clean | - | agora #647: a loop over a struct's Vec field past a callee growing only its elements
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: W { ( Vec ( Vec u ) ) rows String name }

@ growrow W p → v { ( vec_reserve [u] ( vec_at [( Vec u )] . p rows 0 ) 4096 ) }

@ main → i {
    : ( Vec ( Vec u ) ) rs ( vec_new [( Vec u )] )
    ( vec_push [( Vec u )] rs ( vec_new [u] ) )
    ( vec_push [( Vec u )] rs ( vec_new [u] ) )
    : W w @ W { rs ( string_from `a name` ) }
    : ~ i n 0
    ~ r . w rows { ( growrow w ) = n + n ( vec_len [u] r ) }
    ( nurl_println_int n )
    ^ 0
}
