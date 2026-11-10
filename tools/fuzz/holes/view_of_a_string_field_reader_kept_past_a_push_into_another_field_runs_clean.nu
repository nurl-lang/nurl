// view_of_a_string_field_reader_kept_past_a_push_into_another_field_runs_clean: agora #396 — a view of `. t name`'s bytes kept while t's other String field grows: that field's buffer moves, not this one
// Control for agora #396.
// map: §2.10 | A2 | runs-clean | - | agora #396: a view of `. t name`'s bytes kept while t's other String field grows: that field's buffer moves, not this one
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tt { String name String other }

@ main → i {
    : ~ Tt t @ Tt { ( string_from `a heap string in a struct field that will grow` ) ( string_from `the other field` ) }
    : ( Vec s ) o ( vec_new [s] )
    {
        : String f . t name
        ( vec_push [s] o ( string_data f ) )
    }
    : ~ i k 0
    ~ < k 64 { ( string_push_str . t other `more text to make the buffer move` ) = k + k 1 }
    ( nurl_println ( vec_at [s] o 0 ) )
    ^ 0
}
