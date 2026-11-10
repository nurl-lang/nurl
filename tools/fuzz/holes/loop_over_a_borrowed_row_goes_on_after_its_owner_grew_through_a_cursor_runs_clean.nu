// loop_over_a_borrowed_row_goes_on_after_its_owner_grew_through_a_cursor_runs_clean: agora #493 — `~ x row`, row lent out of rows, while rows grows through a cursor: the row's own buffer stays
// Control for agora #493: a container lent out of an owner is a level below the owner's buffer.
// map: §2.5 | A2 | runs-clean | - | agora #493: `~ x row`, row lent out of rows, while rows grows through a cursor: the row's own buffer stays
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ grow ( Vec String ) v → v {
    : ~ i n 0
    ~ < n 64 { ( vec_push [String] v ( string_from `grow` ) ) = n + n 1 }
}

@ main → i {
    : ( Vec String ) t ( vec_new [String] )
    ( vec_push [String] t ( string_from `a string long enough for a heap buffer here` ) )
    ( vec_push [String] t ( string_from `a second string long enough for a heap buffer` ) )
    ( vec_push [String] t ( string_from `a third string long enough for a heap buffer` ) )
    : ~ ( Vec String ) cur t
    : ~ i done 0
    : ~ ( Vec ( Vec String ) ) rows ( vec_new [( Vec String )] )
    ( vec_push [( Vec String )] rows t )
    : ~ ( Vec ( Vec String ) ) rowsc rows
    : ( Vec String ) row ( vec_at [( Vec String )] rows 0 )
    ~ x row {
        : ~ i n 0
        ~ < n 64 { ( vec_push [( Vec String )] rowsc ( vec_new [String] ) ) = n + n 1 }
        ( nurl_println ( string_data x ) )
    }
    ^ 0
}
