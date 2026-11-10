// diag_slice_element_view_read_after_source_grew.nu — a view stored into an
// element of a slice makes the slice depend on what the view points into
// (Agora #545): the slice read after that binding's buffer may have moved
// is refused. It compiled, and the loop printed freed memory.

$ `stdlib/core/string.nu`

@ main → i {
    : ~ [s ws [s | `lit`]
    : ~ String text ( string_from `a string that grows` )
    : i k 0
    = . ws k ( string_data text )
    ~ < ( string_len text ) 4000 { ( string_push_str text `more and more and more text` ) }
    ~ x ws { ( nurl_println x ) }
    ^ 0
}
