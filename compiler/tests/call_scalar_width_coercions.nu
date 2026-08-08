// call_scalar_width_coercions.nu — the LEGAL scalar coercions at call
// boundaries (the binding law applied to calls), pinned as behavior:
//   * f32 argument to an 'f' parameter widens via fpext (lossless);
//   * f argument to an 'f32' parameter narrows via fptrunc;
//   * bool argument to an 'i' parameter zero-extends (T is 1, never -1);
//   * a kwargs default for a 'u' parameter is truncated to i8 (it used
//     to splice a raw `i64` into the call's argument list);
//   * slice-literal elements narrow into a '[ u | … ]' buffer.
@ half f x → f { ^ / x 2.0 }

@ halfs f32 x → f32 { ^ x }

@ widen b c → i { ^ + 10 c }

@ scale i x u k = 5 → i { ^ * x # i k }

@ main → i {
    : f32 a 3.0
    : f fa ( half a )
    ( nurl_print ( nurl_str_float fa ) ) ( nurl_print `\n` )
    : f d 1.5
    : f32 fd ( halfs d )
    ( nurl_print ( nurl_str_float # f fd ) ) ( nurl_print `\n` )
    : b t T
    ( nurl_print ( nurl_str_int ( widen t ) ) ) ( nurl_print `\n` )
    ( nurl_print ( nurl_str_int ( scale x : 4 ) ) ) ( nurl_print `\n` )
    : [u xs [u | 1 2 300]
    : i last 2
    ( nurl_print ( nurl_str_int # i . xs last ) ) ( nurl_print `\n` )
    ^ 0
}
