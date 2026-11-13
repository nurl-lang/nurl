// closure_copy_replacing_the_binding_it_is_handed_is_refused: a copy of a closure giving its capture `o` a new value, called with `o`
// Closed: agora #686, a copy is run by its closure node's effects, #339's check among them; kept with agora #445's routes, whose fix must not lose it.
// main c24c989a: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #445: a copy of a closure called with the binding it replaces
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ( @ v String ) c \ String p → v { = o ( string_from `new` ) ( nurl_println ( string_data p ) ) }
    : ( @ v String ) d c
    ( d o )
    ^ 0
}
