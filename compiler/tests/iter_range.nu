// Test: stdlib/std/iter.nu — range / range_step / range_each
$ `stdlib/std/iter.nu`
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
  // simple ascending
  : ( Vec i ) a ( range 0 5 )
  ( nurl_print `0..5=` ) ( print_vec a )
  ( vec_free [i] a )

  // negative-from
  : ( Vec i ) b ( range -2 3 )
  ( nurl_print `-2..3=` ) ( print_vec b )
  ( vec_free [i] b )

  // empty (from >= to)
  : ( Vec i ) c ( range 5 0 )
  ( nurl_print `5..0=` ) ( print_vec c )
  ( vec_free [i] c )

  // step 2
  : ( Vec i ) d ( range_step 0 10 2 )
  ( nurl_print `step2=` ) ( print_vec d )
  ( vec_free [i] d )

  // negative step
  : ( Vec i ) e ( range_step 10 0 -1 )
  ( nurl_print `down=` ) ( print_vec e )
  ( vec_free [i] e )

  // step 0 → empty (no hang)
  : ( Vec i ) z ( range_step 0 10 0 )
  ( nurl_print `step0_len=` )
  ( nurl_print ( nurl_str_int ( vec_len [i] z ) ) )
  ( nurl_print `\n` )
  ( vec_free [i] z )

  // range_each — sum without allocating a Vec
  : ~ i sum 0
  : (@ v i) accum \ i x → v { = sum + sum x }
  ( range_each 1 11 accum )
  ( nurl_print `range_each_sum_1_to_10=` )
  ( nurl_print ( nurl_str_int sum ) )
  ( nurl_print `\n` )
  // Note: closure captures by value — sum stays 0 in main's scope.
  // The closure mutated its own copy. Use vec_fold for the accumulator
  // pattern (verified in set_generic.nu); demonstrated here so the
  // limitation is visible.

  // Functional pipeline: (range 1 6) → square via vec_map → sum via vec_fold
  : ( Vec i ) r ( range 1 6 )
  : (@ i i) sq \ i x → i { ^ * x x }
  : ( Vec i ) sqs ( vec_map [i i] r sq )
  : (@ i i i) plus \ i acc i x → i { ^ + acc x }
  : i tot ( vec_fold [i i] sqs 0 plus )
  ( nurl_print `sum_of_squares_1..5=` )
  ( nurl_print ( nurl_str_int tot ) )
  ( nurl_print `\n` )
  ( vec_free [i] sqs )
  ( vec_free [i] r )

  ( nurl_print `done\n` )
  ^ 0
}
