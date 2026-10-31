// slice_null_with_len: a null-data Slice literal with a nonzero length.
// map: §6.2 | B | rejected | h54 | null-data Slice literal with nonzero length
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Slice i ) s @ ( Slice i ) { # *i 0 5 }
    ?? ( slice_get [i] s 3 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
