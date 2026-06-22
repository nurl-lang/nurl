// should_fail_slice_generic_arg.nu — a bare slice `[ T` as a generic type
// argument.
//
// The monomorphiser cannot mangle an anonymous slice as a type argument; the
// base-name path would capture the lone `[` and emit garbage IR that only
// clang rejected. parse_type_paren / the call-site loop now reject it at the
// source with the wrap-in-a-struct cure.
: Box [T] { T val }

@ main → i {
    : ( Box [i ) b @ ( Box [i ) { [i | 1 2] }
    ^ 0
}
