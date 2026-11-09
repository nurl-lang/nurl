// loop_element_field_cleared_through_a_cursor_over_it_runs_clean: agora #482 — `~ p ps { : ~ its . p items ( vec_clear [String] its ) … }`: each element's Vec field cleared through a cursor over it; the loop goes on
// The shape the fix must keep: a change made through the loop element itself, or through a borrow of it or of its field, drops its own elements, not the element (agora #482).
// main 21a0fb5: runs clean.
// map: §2.5 | A2 | runs-clean | - | agora #482: a loop element's field cleared through a cursor over it
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: P { ( Vec String ) items i n }

@ main → i {
    : ( Vec P ) ps ( vec_new [P] )
    : ~ P a @ P { ( vec_new [String] ) 1 }
    ( vec_push [String] . a items ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [P] ps a )
    : ~ P b @ P { ( vec_new [String] ) 2 }
    ( vec_push [String] . b items ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [P] ps b )
    ~ p ps {
        : ~ ( Vec String ) its . p items
        ( vec_clear [String] its )
        ( nurl_println_int . p n )
    }
    ^ 0
}
