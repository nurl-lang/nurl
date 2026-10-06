// store_then_read_ok.nu — the legal spellings around a store into an
// aggregate (the control for borrow_store_consume.nu).
//
// 1. After the store the aggregate owns the value: it is read through
//    the aggregate (`. w s`), not through the name it moved out of.
// 2. A literal built as an argument to a function that only reads it: the
//    literal is a view, the binding stays the owner and frees its value.
// 3. A rebinding revives the name: the new value is its own.

$ `stdlib/core/string.nu`

: W { String s }

@ width W w → i { ^ ( string_len . w s ) }

@ main → i {
    : String x ( string_from `hello` )
    : W w @ W { x }
    ( puts ( string_data . w s ) )
    ( puts ( string_data . w s ) )

    : String y ( string_from `view` )
    ( puts ( nurl_str_int ( width @ W { y } ) ) )
    ( string_free y )

    : ~ String z ( string_from `first` )
    : W v @ W { z }
    = z ( string_from `second` )
    ( string_free z )
    ( puts ( string_data . v s ) )
    ^ 0
}
