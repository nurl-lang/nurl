// Storing an f32 through a window of a slice leaves the slice and the
// other windows of it valid: replacing a plain number drops nothing, for
// every scalar element type (f32 included — its instances are named for
// LLVM's `float`).
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/io.nu`

@ main → i {
    : ( Vec f32 ) v ( vec_zeroed [f32] 8 )
    : ( Slice f32 ) all ( slice_from_vec [f32] v )
    : ( Slice f32 ) lo ( slice_window [f32] all 0 4 )
    : ( Slice f32 ) hi ( slice_window [f32] all 4 4 )
    : ~ i k 0
    ~ < k 4 {
        ( slice_put [f32] lo k # f32 # f k )
        ( slice_put [f32] hi k # f32 * 0.5 # f k )
        = k + k 1
    }
    : ~ f s 0.0
    = k 0
    ~ < k 8 { = s + s # f ( slice_at [f32] all k ) = k + k 1 }
    ( nurl_println ( nurl_str_float s ) )  // 0+1+2+3 + 0+0.5+1+1.5
    ^ 0
}
