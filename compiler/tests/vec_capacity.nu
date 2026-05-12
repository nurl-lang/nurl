// Test: stdlib/core/vec.nu — vec_reserve / vec_shrink_to_fit / vec_extend
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ print_vec ( Vec i ) v → v {
  ( nurl_print `[` )
  : i n ( vec_len [i] v )
  : ~ i i 0
  ~ < i n {
    : ? i got ( vec_get [i] v i )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] got 0 ) ) )
    ? < i - n 1 { ( nurl_print `,` ) } {}
    = i + i 1
  }
  ( nurl_print `]` )
}

@ main → i {
  // ── reserve grows cap, leaves len at 0 ──
  : ( Vec i ) a ( vec_new [i] )
  ( nurl_print `before reserve cap=` )
  ( nurl_print ( nurl_str_int ( vec_cap [i] a ) ) )
  ( nurl_print `\n` )

  ( vec_reserve [i] a 10 )
  ( nurl_print `after reserve(10) cap>=10=` )
  ( nurl_print ? >= ( vec_cap [i] a ) 10 `T` `F` )
  ( nurl_print ` len=` )
  ( nurl_print ( nurl_str_int ( vec_len [i] a ) ) )
  ( nurl_print `\n` )

  // negative / zero reserve → no-op
  : i cap_now ( vec_cap [i] a )
  ( vec_reserve [i] a -5 )
  ( vec_reserve [i] a 0 )
  ( nurl_print `reserve_neg_zero_noop=` )
  ( nurl_print ? == ( vec_cap [i] a ) cap_now `T` `F` )
  ( nurl_print `\n` )

  // ── shrink_to_fit: cap drops to len ──
  ( vec_push [i] a 1 )
  ( vec_push [i] a 2 )
  ( vec_push [i] a 3 )
  ( vec_shrink_to_fit [i] a )
  ( nurl_print `shrunk cap=` )
  ( nurl_print ( nurl_str_int ( vec_cap [i] a ) ) )
  ( nurl_print ` len=` )
  ( nurl_print ( nurl_str_int ( vec_len [i] a ) ) )
  ( nurl_print `\n` )

  // shrink an empty vec → cap drops to 0
  : ( Vec i ) e ( vec_with_cap [i] 16 )
  ( vec_shrink_to_fit [i] e )
  ( nurl_print `empty_shrunk cap=` )
  ( nurl_print ( nurl_str_int ( vec_cap [i] e ) ) )
  ( nurl_print `\n` )
  ( vec_free [i] e )

  // ── extend: dst takes a copy of src's elements ──
  : ( Vec i ) dst ( vec_new [i] )
  ( vec_push [i] dst 100 )
  ( vec_push [i] dst 200 )

  : ( Vec i ) src ( vec_new [i] )
  ( vec_push [i] src 7 )
  ( vec_push [i] src 8 )
  ( vec_push [i] src 9 )

  ( vec_extend [i] dst src )
  ( nurl_print `extended dst=` ) ( print_vec dst ) ( nurl_print `\n` )

  // src untouched
  ( nurl_print `src untouched=` ) ( print_vec src ) ( nurl_print `\n` )

  // mutating src after extend doesn't reach dst (no aliasing for trivial types)
  ( vec_set [i] src 0 999 )
  : ? i d2 ( vec_get [i] dst 2 )
  ( nurl_print `dst[2] still 7 = ` )
  ( nurl_print ? == ( opt_unwrap_or [i] d2 -1 ) 7 `T` `F` )
  ( nurl_print `\n` )

  // extend with empty src → dst unchanged
  : ( Vec i ) empty_src ( vec_new [i] )
  : i dlen ( vec_len [i] dst )
  ( vec_extend [i] dst empty_src )
  ( nurl_print `extend_empty_noop=` )
  ( nurl_print ? == ( vec_len [i] dst ) dlen `T` `F` )
  ( nurl_print `\n` )

  ( vec_free [i] empty_src )
  ( vec_free [i] src )
  ( vec_free [i] dst )
  ( vec_free [i] a )
  ( nurl_print `done\n` )
  ^ 0
}
