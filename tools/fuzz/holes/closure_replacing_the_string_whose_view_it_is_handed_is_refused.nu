// closure_replacing_the_string_whose_view_it_is_handed_is_refused: a closure giving its capture `o` a new value, called with `( string_data o )`
// Closed: agora #445, a view of the replaced binding reaches it.
// main c24c989a: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #445: a view of the binding a closure replaces
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ( @ v s ) c \ s p → v { = o ( string_from `new` ) ( nurl_println p ) }
    ( c ( string_data o ) )
    ^ 0
}
