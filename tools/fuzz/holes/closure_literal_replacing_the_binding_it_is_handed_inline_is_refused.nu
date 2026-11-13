// closure_literal_replacing_the_binding_it_is_handed_inline_is_refused: a closure literal written in the call, giving its capture `o` a new value, handed beside `o` to a function that calls it with `o`
// Closed: agora #445, the literal's assignment is an effect on its route.
// main c24c989a: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #445: a literal passed inline beside the binding it replaces
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ app ( @ v String ) f String x → v { ( f x ) }

@ main → i {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    ( app \ String p → v { = o ( string_from `new` ) ( nurl_println ( string_data p ) ) } o )
    ^ 0
}
