// callee_grows_an_element_its_caller_holds_a_handle_of: agora #315 — as callee_grows_an_element_of_its_param, the caller holding the element's handle, not a view of its buffer: the handle reaches the moved buffer (the shape the fix must keep).
// Closed: a grower handed a handle a function read out of its parameter (an element, a field of one, a copy) moves the buffer of an element of that parameter (g_fn_ireallocs, closed over the calls): its caller's views into the argument's elements' buffers end at the call — not its views of the argument's own buffer, nor its element handles (bck_view_end_ind; agora #315).
// main: accepted; ran clean.
// map: §2.10 | A2 | runs-clean | - | agora #315: a callee growing an element its caller holds a handle of
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
    ( grow_first vv )
    ( nurl_println_int ( vec_len [u] e0 ) )
    ( nurl_println_int # i ( vec_at [u] e0 4000 ) )
    ^ 0
}
