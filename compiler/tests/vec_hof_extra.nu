// Test: stdlib/core/vec.nu — vec_map / vec_filter / vec_find / vec_any / vec_all
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
  ( nurl_print `]\n` )
}

@ main → i {
  : ( Vec i ) v ( vec_new [i] )
  ( vec_push [i] v 1 )
  ( vec_push [i] v 2 )
  ( vec_push [i] v 3 )
  ( vec_push [i] v 4 )
  ( vec_push [i] v 5 )

  ( nurl_print `src=` ) ( print_vec v )

  // map: square every element
  : (@ i i) sq \ i x → i { ^ * x x }
  : ( Vec i ) sqs ( vec_map [i i] v sq )
  ( nurl_print `sqs=` ) ( print_vec sqs )
  ( vec_free [i] sqs )

  // filter: keep evens
  : (@ b i) even \ i x → b { ^ == 0 % x 2 }
  : ( Vec i ) evens ( vec_filter [i] v even )
  ( nurl_print `evens=` ) ( print_vec evens )
  ( vec_free [i] evens )

  // find: first > 3
  : (@ b i) gt3 \ i x → b { ^ > x 3 }
  : ? i found ( vec_find [i] v gt3 )
  ( nurl_print `find_gt3=` )
  ?? found {
    T x → { ( nurl_print ( nurl_str_int x ) ) ( nurl_print `\n` ) }
    F → { ( nurl_print `none\n` ) }
  }

  // find: nothing matches
  : (@ b i) gt99 \ i x → b { ^ > x 99 }
  : ? i nf ( vec_find [i] v gt99 )
  ( nurl_print `find_gt99=` )
  ?? nf {
    T x → { ( nurl_print `some?!\n` ) }
    F → { ( nurl_print `none\n` ) }
  }

  // any / all
  ( nurl_print `any_even=` )
  ( nurl_print ? ( vec_any [i] v even ) `T` `F` )
  ( nurl_print ` all_even=` )
  ( nurl_print ? ( vec_all [i] v even ) `T` `F` )
  ( nurl_print `\n` )

  : (@ b i) pos \ i x → b { ^ > x 0 }
  ( nurl_print `all_pos=` )
  ( nurl_print ? ( vec_all [i] v pos ) `T` `F` )
  ( nurl_print `\n` )

  // empty vec
  : ( Vec i ) empty ( vec_new [i] )
  ( nurl_print `empty_any=` )
  ( nurl_print ? ( vec_any [i] empty pos ) `T` `F` )
  ( nurl_print ` empty_all=` )
  ( nurl_print ? ( vec_all [i] empty pos ) `T` `F` )
  ( nurl_print `\n` )
  ( vec_free [i] empty )

  ( vec_free [i] v )
  ( nurl_print `done\n` )
  ^ 0
}
