// inner_loop_element_freed_while_a_view_of_it_lives: agora #490 — `~ row rows { ~ x row { ( string_free x ) } }` with a view of an inner String taken before and read after
// Closed: a `~` loop's element moved out is an element of its container gone: the borrows of that container's elements end, as at `vec_remove` (agora #490).
// main c948ff1: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.5 | A2 | rejected | - | agora #490: `~ row rows { ~ x row { ( string_free x ) } }` with a view of an inner String taken before and read after
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec ( Vec String ) ) rows ( vec_new [( Vec String )] )
    : ( Vec String ) r ( vec_new [String] )
    ( vec_push [String] r ( string_from `an inner loop's element freed, a view of it taken before` ) )
    ( vec_push [( Vec String )] rows r )
    : s v ( string_data ( vec_at [String] ( vec_at [( Vec String )] rows 0 ) 0 ) )
    ~ row rows { ~ x row { ( string_free x ) } }
    ( nurl_println v )
    ^ 0
}
