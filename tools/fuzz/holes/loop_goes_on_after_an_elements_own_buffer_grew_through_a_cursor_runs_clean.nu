// loop_goes_on_after_an_elements_own_buffer_grew_through_a_cursor_runs_clean: agora #493 — `~ x t { ( string_push_str ( vec_at cur 0 ) … ) }`: an element's own buffer moves, t's does not
// Control for agora #493: only the buffer the loop reads its elements from ends its cursor.
// map: §2.5 | A2 | runs-clean | - | agora #493: `~ x t { ( string_push_str ( vec_at cur 0 ) … ) }`: an element's own buffer moves, t's does not
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    ~ x t {
        ( string_push_str ( vec_at [String] cur 0 ) `, and a much longer tail that forces the buffer to move elsewhere` )
        ( nurl_println_int ( string_len x ) )
    }
    ^ 0
}
