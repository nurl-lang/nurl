// bare_view_of_a_loop_element_over_a_lowercase_struct_param_handed_back_by_a_callee_below: agora #471 — `@ f bag b → s { ~ x . b items { ^ ( string_data x ) } … }`, `bag` a struct, defined below its caller; the caller clears `. b items`, then reads the view
// Closed: a caller waits for a callee not walked yet that may hand back a view of a loop element over a parameter of any type but a number, a view, a String or an option of one (__rv_plain_param; agora #471).
// main 9d2e7cd: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #471: a bare view of a loop element over a lowercase-named struct parameter, handed back by a callee below
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: bag { ( Vec String ) items i n }

@ main → i {
    : bag b @ bag { ( vec_new [String] ) 0 }
    ( vec_push [String] . b items ( string_from `a string the caller clears before reading its view` ) )
    : s v ( f b )
    ( vec_clear [String] . b items )
    ( nurl_println v )
    ^ 0
}

@ f bag b → s {
    ~ x . b items { ^ ( string_data x ) }
    ^ `none`
}
