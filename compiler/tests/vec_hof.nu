// Test: stdlib/core/vec.nu — higher-order vec_each, vec_fold
$ `stdlib/core/vec.nu`

@ main → i {
  : ( Vec i ) v ( vec_new [i] )
  ( vec_push [i] v 1 )
  ( vec_push [i] v 2 )
  ( vec_push [i] v 3 )
  ( vec_push [i] v 4 )
  ( vec_push [i] v 5 )

  // vec_each — print each element
  : (@ v i) printer \ i x → v {
    ( nurl_print ( nurl_str_int x ) )
    ( nurl_print ` ` )
  }
  ( vec_each [i] v printer )
  ( nurl_print `\n` )

  // vec_fold — sum
  : (@ i i i) plus \ i a i x → i { ^ + a x }
  : i sum ( vec_fold [i i] v 0 plus )
  ( nurl_print `sum=` )
  ( nurl_print ( nurl_str_int sum ) )
  ( nurl_print `\n` )

  // vec_fold — product
  : (@ i i i) mul \ i a i x → i { ^ * a x }
  : i prod ( vec_fold [i i] v 1 mul )
  ( nurl_print `prod=` )
  ( nurl_print ( nurl_str_int prod ) )
  ( nurl_print `\n` )

  ( vec_free [i] v )
  ( nurl_print `done\n` )
  ^ 0
}
