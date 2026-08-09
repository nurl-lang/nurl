// diag_cast_struct_to_float.nu — '# f' of a struct value. The cast
// path emitted `sitofp %A … to double` for ANY non-float source —
// invalid IR only clang reported, with no source location.
: A { i x }

@ main → i {
    : A a @ A { 3 }
    : f z # f a
    ^ 0
}
