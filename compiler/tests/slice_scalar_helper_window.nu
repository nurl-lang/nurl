// A view of plain numbers handed to a safe helper that stores through it
// does not end the borrows of the other views of the same Vec: a Slice
// never moves its storage, and a number owns nothing to drop.
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/std/floatbits.nu`

@ put ( Slice u ) w i k f v → v { ( slice_put_u32_le w * k 4 ( f32_to_bits # f32 v ) ) }

@ main → i {
    : ( Vec u ) out ( vec_zeroed [u] 32 )
    : ( Slice u ) O ( slice_from_vec [u] out )
    : ~ i b 0
    ~ < b 2 {
        : ( Slice u ) W ( slice_window [u] O * b 16 16 )
        : ~ i j 0
        ~ < j 4 { ( put W j # f + * b 4 j ) = j + j 1 }
        = b + b 1
    }
    : ~ f sum 0.0
    : ~ i k 0
    ~ < k 8 { = sum + sum # f ( bits_to_f32 ( slice_u32_le O * k 4 ) ) = k + k 1 }
    ( nurl_println ( nurl_str_float sum ) )
    ^ 0
}
