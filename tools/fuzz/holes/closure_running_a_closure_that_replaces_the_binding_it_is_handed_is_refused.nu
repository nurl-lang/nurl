// closure_running_a_closure_that_replaces_the_binding_it_is_handed_is_refused: a closure that runs a nested closure giving `o` a new value, called with `o`
// Closed: agora #445, a closure gives a new value to what the closures it runs do (g_clo_run_asg), so #339's check sees it.
// main c24c989a: accepted; ASan reported heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #445: a nested closure replacing the binding the outer one is handed
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
    : ~ String o ( string_from `the owner string long enough for the heap` )
    : ( @ v ) inner \ → v { = o ( string_from `new` ) }
    : ( @ v String ) c \ String p → v { ( inner ) ( nurl_println ( string_data p ) ) }
    ( c o )
    ^ 0
}
