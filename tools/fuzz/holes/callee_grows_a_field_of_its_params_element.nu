// callee_grows_a_field_of_its_params_element: agora #315 — a callee pushing into a Vec field of its parameter's element (`: Row r ( vec_at p 0 )`, `( vec_push . r cells 1 )`); the caller's Slice of that field's buffer read after the call.
// Closed: a grower handed a handle a function read out of its parameter (an element, a field of one, a copy) moves the buffer of an element of that parameter (g_fn_ireallocs, closed over the calls): its caller's views into the argument's elements' buffers end at the call — not its views of the argument's own buffer, nor its element handles (bck_view_end_ind; agora #315).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #315: a callee growing a field of its parameter's element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Row { ( Vec u ) cells }

@ grow_cells ( Vec Row ) p → v {
    : Row r ( vec_at [Row] p 0 )
    : ~ i k 0
    ~ < k 4096 { ( vec_push [u] . r cells 1 ) = k + k 1 }
}

@ main → i {
    : ( Vec Row ) rows ( vec_new [Row] )
    : ( Vec u ) cells ( vec_new [u] )
    ( vec_push [u] cells 7 )
    ( vec_push [Row] rows @ Row { cells } )
    : Row r0 ( vec_at [Row] rows 0 )
    : ( Slice u ) sl ( slice_from_vec [u] . r0 cells )
    ( grow_cells rows )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
