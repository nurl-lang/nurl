// slice_of_a_struct_fields_vec_past_a_callee_growing_it: the caller keeping `( slice_from_vec . w xs )` across a callee reserving `. p xs` through a local
// Closed: a callee whose summary says a buffer at a field path of its parameter may move (g_fn_ifreallocs: a handle it read out of the parameter, not an element of a container there, grown) ends the caller's views of the argument's field paths' own buffers (agora #647).
// main c5115caa: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #647: a slice of a struct's Vec field past a callee growing that field
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/io.nu`

: W { ( Vec i ) xs String name }

@ pushx W p → v { : ( Vec i ) v . p xs ( vec_reserve [i] v 4096 ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    : W w @ W { xs ( string_from `a name` ) }
    : ( Slice i ) sl ( slice_from_vec [i] . w xs )
    ( pushx w )
    ( nurl_println_int ( slice_at [i] sl 0 ) )
    ^ 0
}
