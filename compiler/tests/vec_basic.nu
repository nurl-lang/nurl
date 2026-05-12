// Test: stdlib/core/vec.nu — basic operations on Vec[i]
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ main → i {
  : ( Vec i ) v ( vec_new [i] )

  // initial state
  ( nurl_print `empty=` )
  ( nurl_print ? ( vec_is_empty [i] v ) `T ` `F ` )
  ( nurl_print `len=` )
  ( nurl_print ( nurl_str_int ( vec_len [i] v ) ) )
  ( nurl_print ` cap=` )
  ( nurl_print ( nurl_str_int ( vec_cap [i] v ) ) )
  ( nurl_print `\n` )

  // push 1..5 — cap should grow from 0 → 4 → 8
  ( vec_push [i] v 10 )
  ( vec_push [i] v 20 )
  ( vec_push [i] v 30 )
  ( vec_push [i] v 40 )
  ( vec_push [i] v 50 )

  ( nurl_print `after_push len=` )
  ( nurl_print ( nurl_str_int ( vec_len [i] v ) ) )
  ( nurl_print ` cap=` )
  ( nurl_print ( nurl_str_int ( vec_cap [i] v ) ) )
  ( nurl_print `\n` )

  // iterate via vec_get
  : ~ i i 0
  ~ < i ( vec_len [i] v ) {
    : ? i got ( vec_get [i] v i )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] got 0 ) ) )
    ( nurl_print ` ` )
    = i + i 1
  }
  ( nurl_print `\n` )

  // vec_set
  ( vec_set [i] v 2 999 )
  ( nurl_print `at2=` )
  : ? i g2 ( vec_get [i] v 2 )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] g2 0 ) ) )
  ( nurl_print `\n` )

  // out-of-range get → None
  : ? i oob ( vec_get [i] v 99 )
  ( nurl_print `oob_none=` )
  ?? oob { T x → ( nurl_print `NO\n` )  F → ( nurl_print `YES\n` ) }

  // pop
  : ? i p1 ( vec_pop [i] v )
  ( nurl_print `pop=` )
  ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] p1 0 ) ) )
  ( nurl_print ` len=` )
  ( nurl_print ( nurl_str_int ( vec_len [i] v ) ) )
  ( nurl_print `\n` )

  // swap + reverse
  ( vec_swap [i] v 0 3 )
  ( vec_reverse [i] v )
  ( nurl_print `rev=` )
  = i 0
  ~ < i ( vec_len [i] v ) {
    : ? i got ( vec_get [i] v i )
    ( nurl_print ( nurl_str_int ( opt_unwrap_or [i] got 0 ) ) )
    ( nurl_print ` ` )
    = i + i 1
  }
  ( nurl_print `\n` )

  // clear
  ( vec_clear [i] v )
  ( nurl_print `cleared len=` )
  ( nurl_print ( nurl_str_int ( vec_len [i] v ) ) )
  ( nurl_print ` cap=` )
  ( nurl_print ( nurl_str_int ( vec_cap [i] v ) ) )
  ( nurl_print `\n` )

  ( vec_free [i] v )
  ( nurl_print `done\n` )
  ^ 0
}

