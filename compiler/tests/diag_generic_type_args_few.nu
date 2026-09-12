// diag_generic_type_args_few.nu — a generic struct applied to fewer type
// arguments than it declares.
//
// `Pair` declares two parameters and this type supplies one, so `V` is
// never substituted: the emitted type was `%Pair__i64 = type { i64, %V }`,
// a reference to a type the module never defines. nurlc exited 0 and clang
// reported "use of undefined type named 'V'" with no NURL location.
//
// The generic FUNCTION call path has counted type arguments for years
// ("declares 2 type parameter(s) (K V) but this call supplies 1"). The
// TYPE path is the same question in the other spelling.
: Pair [K V] { K a V b }

@ main → i {
    : i q Z ( Pair i )
    ^ q
}
