// diag_sink_container_beside_a_borrow_of_its_element.nu — a container
// handed to a `sink` parameter, and in the same call a borrow of its
// element, or a closure over one (Agora #494). The callee takes the
// container over and may release it anywhere in its body, elements and
// all; inside the call the borrow is an unrelated name, read after it may
// be gone. Refused as a callee that drops the elements is, naming what to
// pass instead.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ eat_then_read sink ( Vec String ) v String s → i {
    ( vec_free [String] v )
    ^ ( strlen ( string_data s ) )
}

@ eat_then_run sink ( Vec String ) v ( @ i ) f → i {
    ( vec_free [String] v )
    ^ ( f )
}

@ mkv → ( Vec String ) {
    : ~ ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ^ t
}

@ borrow_beside → i {
    : ( Vec String ) t ( mkv )
    : String e ( vec_at [String] t 0 )
    ^ ( eat_then_read t e )
}

@ closure_beside → i {
    : ( Vec String ) t ( mkv )
    : String e ( vec_at [String] t 0 )
    : ( @ i ) f \ → i { ^ ( strlen ( string_data e ) ) }
    ^ ( eat_then_run t f )
}

@ main → i { ^ + ( borrow_beside ) ( closure_beside ) }
