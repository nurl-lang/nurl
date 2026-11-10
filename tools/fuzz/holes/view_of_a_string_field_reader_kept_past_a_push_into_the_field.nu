// view_of_a_string_field_reader_kept_past_a_push_into_the_field: agora #396 — `: String f . t name`, a view of f's bytes stored, then `string_push_str . t name` until its buffer moves: the view was of the field's own buffer (PO r07c)
// main 0b124982: accepted; heap-use-after-free (the view reached t only through an element, `^t`).
// map: §2.10 | A2 | rejected | - | agora #396: `: String f . t name`, a view of f's bytes stored, then `string_push_str . t name` until its buffer moves: the view was of the field's own buffer (PO r07c)
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Tt { String name i n }

@ main → i {
    : ~ Tt t @ Tt { ( string_from `a heap string in a struct field that will grow` ) 1 }
    : ( Vec s ) o ( vec_new [s] )
    {
        : String f . t name
        ( vec_push [s] o ( string_data f ) )
    }
    : ~ i k 0
    ~ < k 64 { ( string_push_str . t name `more text to make the buffer move` ) = k + k 1 }
    ( nurl_println ( vec_at [s] o 0 ) )
    ^ 0
}
