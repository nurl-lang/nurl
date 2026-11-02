// view_stored_into_a_slice_element: agora #415 — `( slice_put [s] sl 0 ( string_data loc ) )`, sl a slice of a Vec read after loc ends
// Closed: a call that writes a Slice's elements, where those elements hold views, is refused outside `unsafe`: what a Slice's elements view is followed nowhere (A2 types slices of elements that hold no views); the Vec stores it where it is followed (agora #415).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #415: `( slice_put [s] sl 0 ( string_data loc ) )`, sl a slice of a Vec read after loc ends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec s ) vs ( vec_new [s] )
    ( vec_push [s] vs `static` )
    {
        : String loc ( string_from `a block local string long enough for the heap, surely` )
        : ( Slice s ) sl ( slice_from_vec [s] vs )
        ( slice_put [s] sl 0 ( string_data loc ) )
    }
    ( nurl_println ( vec_at [s] vs 0 ) )
    ^ 0
}
