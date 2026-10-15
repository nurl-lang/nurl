// Little-endian words in a byte view, slice_to_vec, and a MappedFile's
// view (stdlib/core/slice.nu, stdlib/std/mmap.nu).
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/mmap.nu`

@ main → i {
    : ( Vec u ) b ( vec_zeroed [u] 16 )
    : ( Slice u ) s ( slice_from_vec [u] b )
    ( slice_put_u16_le s 1 0xBEEF )
    ( slice_put_u32_le s 3 0x12345678 )
    ( slice_put_u64_le s 8 -2 )
    ( nurl_println_int ( slice_u16_le s 1 ) )
    ( nurl_println_int ( slice_u32_le s 3 ) )
    ( nurl_println_int ( slice_u64_le s 8 ) )
    ( nurl_println_int ( slice_u32_le s 12 ) )
    // a copy keeps its bytes when the original changes
    : ( Vec u ) c ( slice_to_vec [u] ( slice_window [u] s 3 4 ) )
    ( slice_put_u32_le s 3 0 )
    ( nurl_println_int ( slice_u32_le ( slice_from_vec [u] c ) 0 ) )
    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `kept` ) )
    : ( Vec String ) nc ( slice_to_vec [String] ( slice_from_vec [String] names ) )
    ( vec_clear [String] names )
    ( nurl_println ( string_data ( vec_at [String] nc 0 ) ) )
    // a MappedFile over bytes in memory, and one that could not be opened
    : MappedFile m ( mapped_of_bytes b )
    ( nurl_println_int ( mapped_len m ) )
    ( nurl_println_int ( slice_u64_le ( mapped_bytes m ) 8 ) )
    ?? ( file_map `/nonexistent/nurl-mmap-test` ) {
        T _ → { ( nurl_println `mapped?` ) }
        F _ → { ( nurl_println `missing` ) }
    }
    ^ 0
}
