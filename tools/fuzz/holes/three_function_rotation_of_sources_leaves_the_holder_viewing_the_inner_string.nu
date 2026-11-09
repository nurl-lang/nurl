// three_function_rotation_of_sources_leaves_the_holder_viewing_the_inner_string: three functions rotate three String arguments on each call; the base case stores a view of its first into an inout holder, and the rotation lands it on the caller's inner String.
// Closed: as the two-function form (agora #393). Refused on main 9e8d4a88.
// main d85806eb / 8a2afbc: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #393: a 3-function rotation of source arguments stores a view of the inner String in the caller's holder
$ `stdlib/core/string.nu`

: W { s v }

@ g inout W w String a String b String c i n → v {
    ? > n 0 { ( h w b c a - n 1 ) } { = w @ W { ( string_data a ) } }
}

@ h inout W w String a String b String c i n → v {
    ? > n 0 { ( f w b c a - n 1 ) } { = w @ W { ( string_data a ) } }
}

@ f inout W w String a String b String c i n → v {
    ? > n 0 { ( g w b c a - n 1 ) } { = w @ W { ( string_data a ) } }
}

@ main → i {
    : String outer ( string_from `the outer string which lives long enough here` )
    : String outer2 ( string_from `the second outer string which lives long enough` )
    : ~ W w @ W { `ww` }
    {
        : String inner ( string_from `a long heap string literal that owns a real buffer and is freed here` )
        ( f w outer inner outer2 1 )
    }
    ( nurl_println . w v )
    ^ 0
}
