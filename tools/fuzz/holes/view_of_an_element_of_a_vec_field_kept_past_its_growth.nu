// view_of_an_element_of_a_vec_field_kept_past_its_growth: agora #396 — a view of `( vec_at [String] . t items 0 )`'s bytes stored, then that element grown by string_push_str (the r08 family, the element read directly)
// main 0b124982: rejected already.
// map: §2.10 | A2 | rejected | - | agora #396: a view of `( vec_at [String] . t items 0 )`'s bytes stored, then that element grown by string_push_str (the r08 family, the element read directly)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tt { ( Vec String ) items i n }

@ main → i {
    : ~ Tt t @ Tt { ( vec_new [String] ) 1 }
    ( vec_push [String] . t items ( string_from `a first element long enough for the heap` ) )
    : ( Vec s ) o ( vec_new [s] )
    ( vec_push [s] o ( string_data ( vec_at [String] . t items 0 ) ) )
    : ~ i k 0
    ~ < k 64 { ( string_push_str ( vec_at [String] . t items 0 ) `more text to make the buffer move` ) = k + k 1 }
    ( nurl_println ( vec_at [s] o 0 ) )
    ^ 0
}
