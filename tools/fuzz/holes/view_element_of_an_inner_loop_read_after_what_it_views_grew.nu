// view_element_of_an_inner_loop_read_after_what_it_views_grew: agora #492 — `~ e vvs { grow line  ~ v e { read v } }`, vvs a `( Vec ( Vec s ) )` of views of line
// Closed: a view-class `~` loop element is a borrow of what the container's elements view, as `: s v ( vec_at ws k )` is (agora #492).
// main c948ff1: refused already (the element ends as a holder of views, agora #482).
// map: §2.5 | A2 | rejected | - | agora #492: `~ e vvs { grow line  ~ v e { read v } }`, vvs a `( Vec ( Vec s ) )` of views of line
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : String line ( string_from `a line long enough for a heap buffer` )
    : ( Vec ( Vec s ) ) vvs ( vec_new [( Vec s )] )
    : ( Vec s ) in ( vec_new [s] )
    ( vec_push [s] in ( string_data line ) )
    ( vec_push [( Vec s )] vvs in )
    ~ e vvs {
        : ~ i k 0
        ~ < k 64 { ( string_push_str line ` and a long tail, so the buffer moves` ) = k + k 1 }
        ~ v e { ( nurl_println v ) }
    }
    ^ 0
}
