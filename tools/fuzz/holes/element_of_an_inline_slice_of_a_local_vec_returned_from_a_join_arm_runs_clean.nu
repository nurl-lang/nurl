// element_of_an_inline_slice_of_a_local_vec_returned_from_a_join_arm_runs_clean: `^ ? == c 1 ( slice_at [String] ( slice_from_vec [String] vs ) 0 ) ( string_from `o` )`, vs a local: the arm's call lent out of an inline call, which the join's copy-out rule did not follow.
// Closed (agora #560): an arm's call whose argument is a lend (a view, a call argument's stand-in `__alr#N`) is followed down the chain (mem_join_local_lend): the element is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ ? == c 1 ( slice_at [String] ( slice_from_vec [String] vs ) 0 ) ( string_from `o` )`, vs a local: the arm's call lent out of an inline call, which the join's copy-out rule did not follow (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ mkps → ( Vec P ) { : ( Vec P ) ps ( vec_new [P] ) ( vec_push [P] ps @ P { ( string_from `payload field string long enough` ) } ) ^ ps }

@ mkrs → ( Vec R ) { : ( Vec R ) rs ( vec_new [R] ) ( vec_push [R] rs @ R { @ ?String { T ( string_from `option field string long enough` ) } } ) ^ rs }

@ mkqs → ( Vec Q ) { : ( Vec Q ) qs ( vec_new [Q] ) ( vec_push [Q] qs @ Q { @ P { ( string_from `nested field string long enough` ) } } ) ^ qs }

@ first i c → String { : ( Vec String ) vs ( mkvs ) ^ ? == c 1 ( slice_at [String] ( slice_from_vec [String] vs ) 0 ) ( string_from `o` ) }

@ main → i { : String r ( first 1 ) ( nurl_println ( string_data r ) ) ^ 0 }
