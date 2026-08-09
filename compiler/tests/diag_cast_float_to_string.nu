// diag_cast_float_to_string.nu — '# s' of a float value: the dual of
// the string→float cast, `fptosi double … to i8*` — invalid IR only
// clang reported. Formatting is a runtime call, not a cast.
@ main → i {
    : s z # s 1.5
    ^ 0
}
