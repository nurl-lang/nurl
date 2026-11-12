// sink_container_handed_beside_a_borrow_of_its_element: a Vec handed to a `sink` parameter beside a `vec_at` borrow of its element; the callee frees the Vec, then reads the borrow
// Closed: an argument a `sink` parameter takes over is one whose value the callee may end, elements and all: a borrow of it, a view of it or a closure over one beside it in the same call is refused, as beside a callee that drops the elements (bck_call_alias_check; agora #494).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #494: a Vec handed to a `sink` parameter beside a `vec_at` borrow of its element; the callee frees the Vec, then reads the borrow
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat_then_read sink ( Vec String ) v String s → i { ( vec_free [String] v ) ^ ( strlen ( string_data s ) ) }

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    : String e ( vec_at [String] t 0 )
    ( nurl_println_int ( eat_then_read t e ) )
    ^ 0
}
