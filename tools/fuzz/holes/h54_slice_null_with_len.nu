// H54: a null-data Slice literal with a nonzero length.
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Slice i ) s @ ( Slice i ) { # *i 0 5 }
    ?? ( slice_get [i] s 3 ) { T x → { ( nurl_println_int x ) } F → {} }
    ^ 0
}
