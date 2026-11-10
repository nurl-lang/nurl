// field_of_a_vec_get_payload_returned_from_a_closure_over_its_parameter_runs_clean: `^ . p s` in a closure body, p a `??` payload of `( vec_get [P] qs 0 )` with qs the closure's parameter: the caller took the result as its own and freed what its Vec still held.
// Closed (agora #560): in a closure body a field of a lend handed back is copied, a parameter's included.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ . p s` in a closure body, p a `??` payload of `( vec_get [P] qs 0 )` with qs the closure's parameter: the caller took the result as its own and freed what its Vec still held (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec P ) ps ( vec_new [P] ) ( vec_push [P] ps @ P { ( string_from `payload field string long enough` ) } ) : ( @ String ( Vec P ) ) f \ ( Vec P ) qs → String { ?? ( vec_get [P] qs 0 ) { T p → { ^ . p s } F → { ^ ( string_from `none` ) } } } : String r ( f ps ) ( vec_free [P] ps ) ^ r }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
