// loop_element_freed_while_views_an_earlier_loop_collected_live: agora #490 — an earlier loop pushes `( string_data y )` of each element into a `( Vec s )`; `~ x t { ( string_free x ) }`; the views are read
// Closed: a `~` loop's element moved out is an element of its container gone: the borrows of that container's elements end, as at `vec_remove` (agora #490).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #490: an earlier loop pushes `( string_data y )` of each element into a `( Vec s )`; `~ x t { ( string_free x ) }`; the views are read
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string whose view an earlier loop collected` ) )
    : ( Vec s ) vs ( vec_new [s] )
    ~ y t { ( vec_push [s] vs ( string_data y ) ) }
    ~ x t { ( string_free x ) }
    ~ v vs { ( nurl_println v ) }
    ^ 0
}
