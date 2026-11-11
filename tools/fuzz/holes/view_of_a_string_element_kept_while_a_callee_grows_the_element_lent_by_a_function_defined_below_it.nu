// view_of_a_string_element_kept_while_a_callee_grows_the_element_lent_by_a_function_defined_below_it: the caller keeps an `s` view of the String at `names[0]` (`( string_data ( vec_at [String] names 0 ) )`), then calls a function that binds `( pick names )` and appends to the binding sixteen times, where `pick` — DEFINED BELOW the function — hands back `( vec_at [String] names 0 )`, a lend of its parameter. The appends move the String's buffer; the view is read after the call.
// Guard of agora #646's derived edges on the single-threaded side: a binding of a call to a function with no summary yet is resolved at the module's end against the callee's final lends, so the function is known to grow an element of its parameter and the caller's views into the argument's elements end at the call.
// main: refused too, but only because it took whatever a function not yet summarised hands back as read out of its arguments — it refused the copy twin with it.
// map: §2.10 | A2 | rejected | - | an `s` view of a String element kept across a callee that binds the result of a function defined below it, which lends that element, and appends to the binding (agora #646)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ grow ( Vec String ) names → v {
    : String e ( pick names )
    : ~ i k 0
    ~ < k 16 { ( string_push_str e `, and a tail long enough that the buffer has to move to another place on the heap` ) = k + k 1 }
}

@ pick ( Vec String ) names → String { ^ ( vec_at [String] names 0 ) }

@ main → i {
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `a name long enough to live on the heap, not inline` ) )
    : s w ( string_data ( vec_at [String] names 0 ) )
    ( grow names )
    ( nurl_println w )
    ^ 0
}
