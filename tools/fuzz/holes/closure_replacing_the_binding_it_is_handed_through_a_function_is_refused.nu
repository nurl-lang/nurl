// closure_replacing_the_binding_it_is_handed_through_a_function_is_refused: a closure giving its capture `o` a new value, and `o`, handed to a function that calls the one with the other
// Closed: agora #445, a closure's assignment is an effect on every route the closure runs by, so no other argument of the call may reach what it replaces.
// main c24c989a: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #445: a function calling a closure with the binding it replaces
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ run1 ( @ v String ) f String x → v { ( f x ) }

@ main → i {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ( @ v String ) c \ String p → v { = o ( string_from `new` ) ( nurl_println ( string_data p ) ) }
    ( run1 c o )
    ^ 0
}
