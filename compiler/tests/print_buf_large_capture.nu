// print_buf_large_capture.nu — a capture that holds the whole buffer, past
// its first 64 KB, is handed the buffer itself (nurl_print_buf_stop): the
// next capture writes a fresh buffer, and the first string is untouched.
//
// The first capture is 77,000 bytes, past OUTBUF_INIT_CAP. The second
// writes other text after it. The first string still reads as it was,
// each is its own, and both are released when they go out of scope (the
// ASan + LSan corpus checks the release).

$ `stdlib/core/string.nu`

@ main → i {
    ( nurl_print_buf_start )
    : ~ i k 0
    ~ < k 7000 { ( nurl_print `0123456789\n` ) = k + k 1 }
    : s first ( nurl_print_buf_stop )
    ( nurl_print_buf_start )
    = k 0
    ~ < k 9000 { ( nurl_print `zyxwvutsrq\n` ) = k + k 1 }
    : s second ( nurl_print_buf_stop )
    : String want1 ( string_new )
    = k 0
    ~ < k 7000 { ( string_push_str want1 `0123456789\n` ) = k + k 1 }
    : String want2 ( string_new )
    = k 0
    ~ < k 9000 { ( string_push_str want2 `zyxwvutsrq\n` ) = k + k 1 }
    ( nurl_println_int ( nurl_str_len first ) )
    ( nurl_println_int ( nurl_str_len second ) )
    ? ( nurl_str_eq first ( string_data want1 ) ) { ( nurl_println `first capture intact` ) } { ( nurl_println `first capture overwritten` ) }
    ? ( nurl_str_eq second ( string_data want2 ) ) { ( nurl_println `second capture intact` ) } { ( nurl_println `second capture wrong` ) }
    ( nurl_println `after both captures` )
    ^ 0
}
