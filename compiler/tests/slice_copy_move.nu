// slice_copy_move.nu — core/slice.nu slice_copy / slice_move and
// std/deflate.nu crc32_slice.
//
// slice_copy: the shorter length wins, bytes and owned Strings (deep
// copies, the replaced ones dropped — ASan/LSan see a leak or a double
// free otherwise). slice_move: a run slid right and left inside one view,
// overlapping, the moved-over elements dropped. crc32_slice equals crc32
// of the same bytes, over a window of a larger buffer.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/deflate.nu`

@ show s label i x → v { ( nurl_print label ) ( nurl_println_int x ) }

@ bytes_line ( Vec u ) bs → v {
    ~ x bs { ( nurl_print ( nurl_str_int # i x ) ) ( nurl_print ` ` ) }
    ( nurl_print `\n` )
}

@ main → i {
    : ( Vec u ) a ( vec_new [u] )
    : ~ i k 0
    ~ < k 8 { ( vec_push [u] a # u + k 1 ) = k + k 1 }
    : ( Vec u ) b ( vec_zeroed [u] 5 )
    ( show `copied: ` ( slice_copy [u] ( slice_from_vec [u] b ) ( slice_from_vec [u] a ) ) )
    ( bytes_line b )
    ( slice_move [u] ( slice_from_vec [u] a ) 0 2 5 )
    ( bytes_line a )
    ( slice_move [u] ( slice_from_vec [u] a ) 3 1 5 )
    ( bytes_line a )

    : ( Vec String ) names ( vec_new [String] )
    ( vec_push [String] names ( string_from `ada` ) )
    ( vec_push [String] names ( string_from `bob` ) )
    ( vec_push [String] names ( string_from `cy` ) )
    : ( Vec String ) other ( vec_new [String] )
    ( vec_push [String] other ( string_from `x` ) )
    ( vec_push [String] other ( string_from `y` ) )
    ( show `copied: ` ( slice_copy [String] ( slice_from_vec [String] other ) ( slice_from_vec [String] names ) ) )
    ( slice_move [String] ( slice_from_vec [String] names ) 0 1 2 )
    ~ n names { ( nurl_print ( string_data n ) ) ( nurl_print ` ` ) }
    ~ n other { ( nurl_print ( string_data n ) ) ( nurl_print ` ` ) }
    ( nurl_print `\n` )

    : ( Vec u ) big ( vec_new [u] )
    = k 0
    ~ < k 300 { ( vec_push [u] big # u & * k 7 255 ) = k + k 1 }
    : ( Vec u ) part ( vec_new [u] )
    = k 10
    ~ < k 210 { ( vec_push [u] part ( vec_at [u] big k ) ) = k + k 1 }
    ( show `crc equal: ` ? == ( crc32 part ) ( crc32_slice ( slice_window [u] ( slice_from_vec [u] big ) 10 200 ) ) 1 0 )
    ( show `crc chain: ` ? == ( crc32 big ) ( crc32_update_slice ( crc32_slice ( slice_window [u] ( slice_from_vec [u] big ) 0 100 ) ) ( slice_window [u] ( slice_from_vec [u] big ) 100 200 ) ) 1 0 )
    ^ 0
}
