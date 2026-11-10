// view_of_an_element_through_a_vec_field_reader_kept_past_its_growth: agora #396 — the same through a field reader, `: ( Vec String ) f . t items` (the r08 family, through a borrow)
// main 0b124982: rejected already.
// map: §2.10 | A2 | rejected | - | agora #396: the same through a field reader, `: ( Vec String ) f . t items` (the r08 family, through a borrow)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tt { ( Vec String ) items i n }

@ main → i {
    : ~ Tt t @ Tt { ( vec_new [String] ) 1 }
    ( vec_push [String] . t items ( string_from `a first element long enough for the heap` ) )
    : ( Vec s ) o ( vec_new [s] )
    {
        : ( Vec String ) f . t items
        ( vec_push [s] o ( string_data ( vec_at [String] f 0 ) ) )
    }
    : ~ i k 0
    ~ < k 64 { ( string_push_str ( vec_at [String] . t items 0 ) `more text to make the buffer move` ) = k + k 1 }
    ( nurl_println ( vec_at [s] o 0 ) )
    ^ 0
}
