// mutual_recursion_swapping_sources_leaves_the_holder_viewing_the_inner_string: two mutually recursive functions swap their String arguments on each call and store a view of one into an inout holder at the base case; the caller passes an inner String that ends first (PO probe p20).
// Closed: a cycle's answers settle as a fixed point over the component with each call's argument permutation (github#1605), so the caller's holder is seen to view the inner String (agora #393). Refused on main 9e8d4a88.
// main d85806eb / 8a2afbc: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.7 | A2 | rejected | - | agora #393: mutual recursion that swaps its source arguments stores a view of the inner String in the caller's holder
$ `stdlib/core/string.nu`

: W { s v }

@ g inout W w String a String b i n → v {
    ? > n 0 { ( f w b a - n 1 ) } { = w @ W { ( string_data a ) } }
}

@ f inout W w String a String b i n → v {
    ? > n 0 { ( g w b a - n 1 ) } { = w @ W { ( string_data a ) } }
}

@ main → i {
    : String outer ( string_from `the outer string which lives long enough here` )
    : ~ W w @ W { `ww` }
    {
        : String inner ( string_from `a long heap string literal that owns a real buffer and is freed here` )
        ( f w outer inner 1 )
    }
    ( nurl_println . w v )
    ^ 0
}
