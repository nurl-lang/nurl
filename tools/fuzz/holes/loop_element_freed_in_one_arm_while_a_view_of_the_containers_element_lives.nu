// loop_element_freed_in_one_arm_while_a_view_of_the_containers_element_lives: agora #490 — `~ x t { ? c { ( string_free x ) } {} }` with a view of t's element taken before and read after
// Closed: a `~` loop's element moved out is an element of its container gone: the borrows of that container's elements end, as at `vec_remove` (agora #490).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #490: `~ x t { ? c { ( string_free x ) } {} }` with a view of t's element taken before and read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string freed in one arm only, through its loop element` ) )
    : s v ( string_data ( vec_at [String] t 0 ) )
    : ~ i n 0
    ~ x t { ? == n 0 { ( string_free x ) } {} = n + n 1 }
    ( nurl_println v )
    ^ 0
}
