// field_of_a_vec_get_payload_returned_from_a_closure_over_a_capture_runs_clean: `^ . p s` in a closure body, p a `??` payload of `( vec_get [P] ps 0 )` with ps a captured local.
// Closed (agora #560): in a closure body a field of a lend handed back is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ . p s` in a closure body, p a `??` payload of `( vec_get [P] ps 0 )` with ps a captured local (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec P ) ps ( vec_new [P] ) ( vec_push [P] ps @ P { ( string_from `payload field string long enough` ) } ) : ( @ String ) f \ → String { ?? ( vec_get [P] ps 0 ) { T p → { ^ . p s } F → { ^ ( string_from `none` ) } } } : String r ( f ) ^ r }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
