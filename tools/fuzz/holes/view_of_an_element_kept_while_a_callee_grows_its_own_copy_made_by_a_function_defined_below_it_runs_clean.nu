// view_of_an_element_kept_while_a_callee_grows_its_own_copy_made_by_a_function_defined_below_it_runs_clean: the caller keeps a Slice over the Vec at `vv[0]`, then calls a function that binds `( copy_of p )` and pushes 4096 times to the binding, where `copy_of` — DEFINED BELOW the function — hands back a `vec_clone` of that element. The function grows a copy of its own; the element the Slice views is untouched, and the Slice is read after the call.
// The control for view_of_an_element_kept_while_a_callee_grows_the_element_lent_by_a_function_defined_below_it: a callee that lends nothing leaves the binding the function's own, and the function changes nothing of its parameter.
// main: refused — "'sl' borrows from 'vv', which ended … it was passed to 'grow', which may move the buffer of one of its elements".
// map: §2.10 | A2 | runs-clean | - | a Slice over an element kept across a callee that binds the result of a function defined below it, which hands back a `vec_clone` of that element, and pushes to the binding: a change of a copy (agora #646)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow ( Vec ( Vec u ) ) p → i {
    : ( Vec u ) e ( copy_of p )
    : ~ i k 0
    ~ < k 4096 { ( vec_push [u] e 1 ) = k + k 1 }
    ^ ( vec_len [u] e )
}

@ copy_of ( Vec ( Vec u ) ) p → ( Vec u ) { ^ ( vec_clone [u] ( vec_at [( Vec u )] p 0 ) ) }

@ main → i {
    : ( Vec ( Vec u ) ) vv ( vec_new [( Vec u )] )
    : ( Vec u ) inner ( vec_new [u] )
    ( vec_push [u] inner 7 )
    ( vec_push [( Vec u )] vv inner )
    : ( Vec u ) e0 ( vec_at [( Vec u )] vv 0 )
    : ( Slice u ) sl ( slice_from_vec [u] e0 )
    : i n ( grow vv )
    ^ ? & == n 4097 == # i ( slice_at [u] sl 0 ) 7 0 1
}
