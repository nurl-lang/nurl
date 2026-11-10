// diag_slice_literal_view_read_after_source_grew.nu — a slice literal that
// holds a view of a binding depends on it (Agora #545): read after the
// binding's buffer may have moved, it is refused. The elements of a native
// slice were followed nowhere, so this compiled and read freed memory.

$ `stdlib/core/string.nu`

@ main → i {
    : ~ String text ( string_from `a view in a slice of raw strings` )
    : [s ws [s | ( string_data text ) `lit`]
    ~ < ( string_len text ) 4000 { ( string_push_str text `more and more and more text` ) }
    ~ x ws { ( nurl_println x ) }
    ^ 0
}
