// sink_container_handed_beside_a_closure_over_its_element: a Vec handed to a `sink` parameter beside a closure over a borrow of its element; the callee frees the Vec, then runs the closure
// Closed: an argument a `sink` parameter takes over is one whose value the callee may end, elements and all: a borrow of it, a view of it or a closure over one beside it in the same call is refused, as beside a callee that drops the elements (bck_call_alias_check; agora #494).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.4 | A2 | rejected | - | agora #494: a Vec handed to a `sink` parameter beside a closure over a borrow of its element; the callee frees the Vec, then runs the closure
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat_then_read sink ( Vec String ) v String s → i { ( vec_free [String] v ) ^ ( strlen ( string_data s ) ) }

@ eat_then_run sink ( Vec String ) v ( @ i ) f → i { ( vec_free [String] v ) ^ ( f ) }

@ mkv → ( Vec String ) { : ~ ( Vec String ) t ( vec_new [String] ) ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) ) ^ t }

: H { ( Vec String ) items i n }

@ main → i {
    : ( Vec String ) t ( mkv )
    : String e ( vec_at [String] t 0 )
    : ( @ i ) f \ → i { ^ ( strlen ( string_data e ) ) }
    ^ - ( eat_then_run t f ) 43
}
