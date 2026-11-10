// loop_element_handed_to_a_sink_while_a_view_of_the_containers_element_lives: agora #490 — `~ x t { ( consume x ) }`, consume taking a `sink String`, with a view of t's element taken before and read after
// Closed: a `~` loop's element moved out is an element of its container gone: the borrows of that container's elements end, as at `vec_remove` (agora #490).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #490: `~ x t { ( consume x ) }`, consume taking a `sink String`, with a view of t's element taken before and read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ consume sink String x → v {}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string handed to a sink through its loop element` ) )
    : s v ( string_data ( vec_at [String] t 0 ) )
    ~ x t { ( consume x ) }
    ( nurl_println v )
    ^ 0
}
