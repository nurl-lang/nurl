// diag_optlit_int_to_float_payload.nu — an integer payload in an
// option literal whose declared payload type is float: the dual of the
// float→int case. '@ ?f { T 3 }' emitted a raw insertvalue of an i64
// into a double slot — invalid IR only clang reported, three build
// stages later.
@ main → i {
    : ?f o @ ?f { T 3 }
    ^ 0
}
