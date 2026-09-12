// diag_generic_type_args_many.nu — a generic struct applied to more type
// arguments than it declares.
//
// The surplus is worse than ignored: the DEFINITION is mangled from the
// declared parameters (`%Box__i64`) while every REFERENCE carries all the
// arguments written (`%Box__i64__f64`), so the module referenced a named
// type nothing defined. nurlc exited 0; clang said "base element of
// getelementptr must be sized".
: Box [T] { T v }

@ main → i {
    : i q Z ( Box i f )
    ^ q
}
