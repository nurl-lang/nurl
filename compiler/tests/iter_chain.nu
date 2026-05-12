// Test: stdlib/std/iter.nu — lazy ( Iter A ) ≡ (@ ? A i) chain with auto-drop
//
// Single closure carries both advance (cmd=0) and free (cmd=1) paths.
// Constructors allocate state via nurl_zalloc and free it via cmd=1.
// Combinators cascade cmd=1 to upstream. Consumers auto-issue cmd=1
// after exhaustion. Result: state buffers do NOT leak. Closure envs
// are still per-pipeline (constant overhead).

$ `stdlib/std/iter.nu`

@ print_vec_i ( Vec i ) v → v {
  ( nurl_print `[` )
  : i n ( vec_len [i] v )
  : ~ i i 0
  ~ < i n {
    : ? i got ( vec_get [i] v i )
    ?? got {
      T x → { ( nurl_print ( nurl_str_int x ) ) }
      F → {}
    }
    ? < i - n 1 { ( nurl_print `,` ) } {}
    = i + i 1
  }
  ( nurl_print `]\n` )
}

@ print_opt_i ? i o s label → v {
  ( nurl_print label )
  ?? o {
    T v → { ( nurl_print `=Some(` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `)\n` ) }
    F   → { ( nurl_print `=None\n` ) }
  }
}

@ main → i {
  // ── iter_range + iter_collect ──
  : ( Vec i ) v1 ( iter_collect [i] ( iter_range 0 5 ) )
  ( nurl_print `range_collect=` ) ( print_vec_i v1 )
  ( vec_free [i] v1 )

  // ── iter_range_step descending ──
  : ( Vec i ) v2 ( iter_collect [i] ( iter_range_step 10 0 -2 ) )
  ( nurl_print `step_desc=` ) ( print_vec_i v2 )
  ( vec_free [i] v2 )

  // ── zero-step empty ──
  ( nurl_print `step0_count=` ) ( nurl_print ( nurl_str_int ( iter_count [i] ( iter_range_step 0 10 0 ) ) ) ) ( nurl_print `\n` )

  // ── iter_repeat ──
  : ( Vec i ) v_rep ( iter_collect [i] ( iter_repeat [i] 7 4 ) )
  ( nurl_print `repeat=` ) ( print_vec_i v_rep )
  ( vec_free [i] v_rep )

  // ── iter_map (square) ──
  : (@ i i) sq \ i x → i { ^ * x x }
  : ( Vec i ) v_sqs ( iter_collect [i] ( iter_map [i i] ( iter_range 1 6 ) sq ) )
  ( nurl_print `squares=` ) ( print_vec_i v_sqs )
  ( vec_free [i] v_sqs )

  // ── iter_filter (even) ──
  : (@ b i) is_even \ i x → b { ^ == 0 % x 2 }
  : ( Vec i ) v_e ( iter_collect [i] ( iter_filter [i] ( iter_range 0 10 ) is_even ) )
  ( nurl_print `evens=` ) ( print_vec_i v_e )
  ( vec_free [i] v_e )

  // ── iter_take ──
  : ( Vec i ) v_tk ( iter_collect [i] ( iter_take [i] ( iter_range 0 100 ) 4 ) )
  ( nurl_print `take4=` ) ( print_vec_i v_tk )
  ( vec_free [i] v_tk )

  // ── iter_take where n > available ──
  : ( Vec i ) v_tk2 ( iter_collect [i] ( iter_take [i] ( iter_range 0 3 ) 100 ) )
  ( nurl_print `take_short=` ) ( print_vec_i v_tk2 )
  ( vec_free [i] v_tk2 )

  // ── iter_skip ──
  : ( Vec i ) v_sk ( iter_collect [i] ( iter_skip [i] ( iter_range 0 7 ) 3 ) )
  ( nurl_print `skip3=` ) ( print_vec_i v_sk )
  ( vec_free [i] v_sk )

  // ── iter_skip overshoot ──
  ( nurl_print `skip_overshoot_count=` ) ( nurl_print ( nurl_str_int ( iter_count [i] ( iter_skip [i] ( iter_range 0 3 ) 10 ) ) ) ) ( nurl_print `\n` )

  // ── iter_chain ──
  : ( Vec i ) v_ch ( iter_collect [i] ( iter_chain [i] ( iter_range 0 3 ) ( iter_range 100 103 ) ) )
  ( nurl_print `chain=` ) ( print_vec_i v_ch )
  ( vec_free [i] v_ch )

  // ── iter_fold ──
  : (@ i i i) plus \ i acc i x → i { ^ + acc x }
  ( nurl_print `fold_sum_1_10=` ) ( nurl_print ( nurl_str_int ( iter_fold [i i] ( iter_range 1 11 ) 0 plus ) ) ) ( nurl_print `\n` )

  // ── iter_sum_i ──
  ( nurl_print `sum_1_10=` ) ( nurl_print ( nurl_str_int ( iter_sum_i ( iter_range 1 11 ) ) ) ) ( nurl_print `\n` )

  // ── iter_count ──
  ( nurl_print `count_0_42=` ) ( nurl_print ( nurl_str_int ( iter_count [i] ( iter_range 0 42 ) ) ) ) ( nurl_print `\n` )

  // ── iter_each ──
  : s side ( nurl_zalloc 8 )
  ( nurl_poke side 0 0 )
  : (@ v i) accum \ i x → v {
    : i cur ( nurl_peek side 0 )
    ( nurl_poke side 0 + cur x )
  }
  ( iter_each [i] ( iter_range 1 6 ) accum )
  ( nurl_print `each_sum_1_5=` ) ( nurl_print ( nurl_str_int ( nurl_peek side 0 ) ) ) ( nurl_print `\n` )
  ( nurl_free side )

  // ── iter_any / iter_all ──
  : (@ b i) gt5  \ i x → b { ^ > x 5 }
  : (@ b i) gt99 \ i x → b { ^ > x 99 }
  ( nurl_print `any_gt5=`  ) ( nurl_print ? ( iter_any [i] ( iter_range 0 10 ) gt5  ) `T` `F` ) ( nurl_print `\n` )
  ( nurl_print `any_gt99=` ) ( nurl_print ? ( iter_any [i] ( iter_range 0 10 ) gt99 ) `T` `F` ) ( nurl_print `\n` )
  : (@ b i) ge0 \ i x → b { ^ >= x 0 }
  ( nurl_print `all_ge0=`  ) ( nurl_print ? ( iter_all [i] ( iter_range 0 10 ) ge0 ) `T` `F` ) ( nurl_print `\n` )
  ( nurl_print `all_gt5=`  ) ( nurl_print ? ( iter_all [i] ( iter_range 0 10 ) gt5 ) `T` `F` ) ( nurl_print `\n` )

  // ── iter_find ──
  : (@ b i) eq7 \ i x → b { ^ == x 7 }
  ( print_opt_i ( iter_find [i] ( iter_range 0 20 ) eq7 )  `find_eq7` )
  ( print_opt_i ( iter_find [i] ( iter_range 0 5  ) eq7 )  `find_miss` )

  // ── iter_from_vec + chained pipeline ──
  : ( Vec i ) src_v ( vec_new [i] )
  ( vec_push [i] src_v 3 ) ( vec_push [i] src_v 1 ) ( vec_push [i] src_v 4 )
  ( vec_push [i] src_v 1 ) ( vec_push [i] src_v 5 ) ( vec_push [i] src_v 9 )
  ( vec_push [i] src_v 2 ) ( vec_push [i] src_v 6 )
  : (@ b i) gt2  \ i x → b { ^ > x 2 }
  ( nurl_print `pipeline_sum=` )
  ( nurl_print ( nurl_str_int ( iter_sum_i
    ( iter_map [i i] ( iter_filter [i] ( iter_from_vec [i] src_v ) gt2 ) sq ) ) ) )
  ( nurl_print `\n` )
  ( vec_free [i] src_v )

  // ── iter_free abandon mid-stream ──
  : (@ ? i i) ab ( iter_take [i] ( iter_range 0 1000000 ) 3 )
  : ? i a1 ( ab 0 )
  ?? a1 {
    T v → { ( nurl_print `abandon_first=` ) ( nurl_print ( nurl_str_int v ) ) ( nurl_print `\n` ) }
    F → {}
  }
  ( iter_free [i] ab )

  ( nurl_print `done\n` )
  ^ 0
}
