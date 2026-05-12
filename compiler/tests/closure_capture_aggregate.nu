// Test: closure capture supports struct-typed values (Set/Vec handles)
// AND closure-typed values (the hash_fn / eq_fn closures themselves).
//
// Before this support, env-struct fields were forced to i64 via ptrtoint,
// which LLVM rejects for aggregate types. Now each capture is stored in
// the env with its native LLVM type.

$ `stdlib/std/set.nu`
$ `stdlib/core/vec.nu`

@ main → i {
  : (@ i i)   hi \ i x → i { ^ ( hash_int x ) }
  : (@ b i i) ei \ i a i b → b { ^ ( eq_int a b ) }

  : ( Set i ) s ( set_new [i] )
  ( set_add [i] s 10 hi ei )
  ( set_add [i] s 20 hi ei )
  ( set_add [i] s 30 hi ei )

  // The closure captures three aggregate values:
  //   s  — struct handle  ( Set i )
  //   hi — closure value  (@ i i)
  //   ei — closure value  (@ b i i)
  : (@ v i) check \ i x → v {
    ( nurl_print `has_` )
    ( nurl_print ( nurl_str_int x ) )
    ( nurl_print `=` )
    ( nurl_print ? ( set_contains [i] s x hi ei ) `T` `F` )
    ( nurl_print ` ` )
  }
  ( check 10 )
  ( check 20 )
  ( check 99 )
  ( nurl_print `\n` )

  // Capture a Vec handle and demonstrate aggregate ownership flowing
  // through the closure environment.
  : ( Vec i ) v ( vec_new [i] )
  ( vec_push [i] v 1 )
  ( vec_push [i] v 2 )
  ( vec_push [i] v 3 )
  : (@ v i) push_doubled \ i x → v {
    ( vec_push [i] v * x 2 )
  }
  ( push_doubled 10 )
  ( push_doubled 20 )
  ( nurl_print `vec_len=` )
  ( nurl_print ( nurl_str_int ( vec_len [i] v ) ) )
  ( nurl_print `\n` )

  ( vec_free [i] v )
  ( set_free [i] s )
  ( nurl_print `done\n` )
  ^ 0
}
