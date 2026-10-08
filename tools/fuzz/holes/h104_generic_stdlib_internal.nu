// H104: a generic stdlib internal (`__vec_grow`) called from safe code takes a short string's bytes for a Vec's control block.
$ `stdlib/core/string.nu`

@ main → i {
    : String s ( string_from `x` )
    ( __vec_grow [u] ( string_data s ) 4096 )
    ( nurl_println_int ( string_len s ) )
    ^ 0
}
