// view_of_a_string_element_kept_while_a_callee_grows_its_own_copy_made_by_a_function_defined_below_it_runs_clean: the caller keeps an `s` view of the String at `names[0]`, then calls a function that binds `( copy_of names )` and appends to the binding sixteen times, where `copy_of` — DEFINED BELOW the function — hands back a `string_clone` of that element. The function grows a copy of its own; the String the view was read out of is untouched, and the view is read after the call.
// The control for view_of_a_string_element_kept_while_a_callee_grows_the_element_lent_by_a_function_defined_below_it: a callee that lends nothing leaves the binding the function's own, and the function changes nothing of its parameter.
// main: refused — "'w' borrows from 'names', which ended … it was passed to 'grow', which may move the buffer of one of its elements".
// map: §2.10 | A2 | runs-clean | - | an `s` view of a String element kept across a callee that binds the result of a function defined below it, which hands back a `string_clone` of that element, and appends to the binding: a change of a copy (agora #646)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ grow ( Vec String ) names → i {
    : String e ( copy_of names )
    : ~ i k 0
    ~ < k 16 { ( string_push_str e `, and a tail long enough that the buffer has to move to another place on the heap` ) = k + k 1 }
    ^ ( string_len e )
}

@ copy_of ( Vec String ) names → String { ^ ( string_clone ( vec_at [String] names 0 ) ) }

@ main → i {
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `a name long enough to live on the heap, not inline` ) )
    : s w ( string_data ( vec_at [String] names 0 ) )
    : i n ( grow names )
    ( nurl_println w )
    ^ ? > n 1000 0 1
}
