// callee_grows_an_element_of_its_param: agora #315 — a callee pushing 4096 values into its parameter's element through a local; the caller's Slice of that element's buffer read after the call.
// Closed: a grower handed a handle a function read out of its parameter (an element, a field of one, a copy) moves the buffer of an element of that parameter (g_fn_ireallocs, closed over the calls): its caller's views into the argument's elements' buffers end at the call — not its views of the argument's own buffer, nor its element handles (bck_view_end_ind; agora #315).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #315: a callee growing an element of its parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow_first ( Vec ( Vec u ) ) p → v {
    : ( Vec u ) e ( vec_at [( Vec u )] p 0 )
    : ~ i k 0
    ~ < k 4096 { ( vec_push [u] e 1 ) = k + k 1 }
}

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    ( vec_push [( Vec u )] vv inner )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    ( grow_first vv )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
