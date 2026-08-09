// diag_bind_struct_cross.nu — binding a value of one named struct to a
// declaration of another. The binding-position dual of the call-site
// and return-site wrong-struct checks: `store %B … into %A*` was
// invalid IR only clang reported.
: A { i x }
: B { i y }

@ main → i {
    : B b @ B { 3 }
    : A a b
    ^ 0
}
