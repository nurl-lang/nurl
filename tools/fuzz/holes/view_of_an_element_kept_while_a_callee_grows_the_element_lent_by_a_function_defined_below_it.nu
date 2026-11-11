// view_of_an_element_kept_while_a_callee_grows_the_element_lent_by_a_function_defined_below_it: the caller keeps a Slice over the Vec at `vv[0]`, then calls a function that binds `( pick p )` and pushes 4096 times to the binding, where `pick` — DEFINED BELOW the function — hands back `( vec_at [( Vec u )] p 0 )`, a lend of its parameter. The pushes move the buffer the Slice views; the Slice is read after the call.
// Guard of agora #646's derived edges on the single-threaded side: a binding of a call to a function with no summary yet is resolved at the module's end against the callee's final lends, so the function is known to grow an element of its parameter and the caller's views into the argument's elements end at the call.
// main: refused too, but only because it took whatever a function not yet summarised hands back as read out of its arguments — it refused the copy twin with it.
// map: §2.10 | A2 | rejected | - | a Slice over an element kept across a callee that binds the result of a function defined below it, which lends that element, and pushes to the binding (agora #646)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow ( Vec ( Vec u ) ) p → v {
    : ( Vec u ) e ( pick p )
    : ~ i k 0
    ~ < k 4096 { ( vec_push [u] e 1 ) = k + k 1 }
}

@ pick ( Vec ( Vec u ) ) p → ( Vec u ) { ^ ( vec_at [( Vec u )] p 0 ) }

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    ( vec_push [( Vec u )] vv inner )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    ( grow vv )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
