// diag_cast_string_to_float.nu — '# f' of a string value: an
// address's bytes have no numeric meaning, and the emitted
// `sitofp i8* … to double` was invalid IR only clang saw. The cure
// names the runtime parse the user almost certainly meant.
@ main → i {
    : s t `3.14`
    : f z # f t
    ^ 0
}
