// H262: a float passed where a parameter is a struct by value (`( first x )`, `f x`, a `( Slice u )` parameter) compiled to an ill-typed call: the callee read the double as the slice — a garbage pointer and length (h188 rejected integers only).
// Closed: any number, integer or float, is rejected where a struct is expected.
// main's compiler: printed a stack address as the slice length.
$ `stdlib/core/io.nu`
$ `stdlib/core/slice.nu`

@ first ( Slice u ) s → i { ^ ( slice_len [u] s ) }

@ main → i {
    : f x 4096.0
    ( nurl_println_int ( first x ) )
    ^ 0
}
