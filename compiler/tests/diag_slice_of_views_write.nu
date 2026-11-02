// diag_slice_of_views_write.nu — a view stored into a Slice's elements is refused
// outside unsafe (agora #415): what a Slice's elements view is followed
// nowhere, so the message points to the Vec that owns the storage.

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
