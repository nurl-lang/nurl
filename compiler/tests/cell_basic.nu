// cell_basic.nu — Cell byte-buffer round-trip + native_sizeof.

$ `stdlib/core/cell.nu`

@ main → i {
    // cell_zero gives a zeroed buffer; reads come back as 0.
    : Cell c ( cell_zero 32 )
    ( nurl_print `size=` ) ( nurl_print ( nurl_str_int ( cell_size c ) ) )
    ( nurl_print ` is_null=` ) ( nurl_print ? ( cell_is_null c ) `T` `F` )
    ( nurl_print `\n` )

    // Byte writes / reads.
    ( cell_write_u8 c 0 65 )  // 'A'
    ( cell_write_u8 c 1 66 )  // 'B'
    ( cell_write_u8 c 31 255 )
    ( nurl_print `[0]=` ) ( nurl_print ( nurl_str_int ( cell_read_u8 c 0 ) ) )
    ( nurl_print ` [1]=` ) ( nurl_print ( nurl_str_int ( cell_read_u8 c 1 ) ) )
    ( nurl_print ` [31]=` ) ( nurl_print ( nurl_str_int ( cell_read_u8 c 31 ) ) )
    ( nurl_print ` [oob]=` ) ( nurl_print ( nurl_str_int ( cell_read_u8 c 32 ) ) )
    ( nurl_print `\n` )

    // cell_zero_fill returns the buffer to all zeros.
    ( cell_zero_fill c )
    ( nurl_print `after zero_fill [1]=` ) ( nurl_print ( nurl_str_int ( cell_read_u8 c 1 ) ) )
    ( nurl_print ` [31]=` ) ( nurl_print ( nurl_str_int ( cell_read_u8 c 31 ) ) )
    ( nurl_print `\n` )

    // Platform-opaque sizing: pthread_mutex_t exists on every POSIX
    // target NURL supports; the exact size varies, so just print
    // whether it's > 0 to keep the test platform-stable.
    : i mt_sz ( nurl_native_sizeof `pthread_mutex_t` )
    ( nurl_print `pthread_mutex_t size>0 = ` ) ( nurl_print ? > mt_sz 0 `T` `F` )
    ( nurl_print `\n` )

    : i ct_sz ( nurl_native_sizeof `pthread_cond_t` )
    ( nurl_print `pthread_cond_t size>0 = ` ) ( nurl_print ? > ct_sz 0 `T` `F` )
    ( nurl_print `\n` )

    // Unknown name → -1 sentinel.
    : i unknown_sz ( nurl_native_sizeof `not_a_real_type_blah` )
    ( nurl_print `unknown = ` ) ( nurl_print ( nurl_str_int unknown_sz ) )
    ( nurl_print `\n` )

    // cell_for_native sizes itself off a known type; allocation
    // should succeed (ptr non-null).
    : Cell mt ( cell_for_native `pthread_mutex_t` )
    ( nurl_print `mt cell is_null=` ) ( nurl_print ? ( cell_is_null mt ) `T` `F` )
    ( nurl_print ` size=` ) ( nurl_print ? > ( cell_size mt ) 0 `>0` `0` )
    ( nurl_print `\n` )

    ( cell_free mt )
    ( cell_free c )
    ( nurl_print `done\n` )
    ^ 0
}
