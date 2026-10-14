// should_fail_pointer_as_struct_arg.nu — h268.
//
// A raw pointer passed where a parameter is a struct by value (`*f` into
// a `( Slice f )`) compiled to an ill-typed call: the callee read the
// address as the slice's data pointer and whatever followed in the
// registers as its length. Every other pointer/value pairing was checked
// (a `*T` for its own `T`, a String for a C string, two named types); a
// pointer against an unrelated struct was not. It is rejected now.
$ `stdlib/core/io.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ first ( Slice f ) s → f { ^ ( slice_at [f] s 0 ) }

unsafe @ main → i {
    : ( Vec f ) v ( vec_zeroed [f] 4 )
    : *f p ( vec_data [f] v )
    ( nurl_println_int # i ( first p ) )
    ^ 0
}
