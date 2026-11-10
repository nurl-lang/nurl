// field_of_a_vec_get_payload_returned_from_a_closure_over_its_local_runs_clean: `^ . p s` in a closure body, p a `??` payload of `( vec_get [P] ps 0 )` with ps a local of the body: the copy-out rule skipped closure bodies.
// Closed (agora #560): in a closure body a field of a lend handed back is copied, whatever it was lent out of: callers take a closure's every result as their own.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ . p s` in a closure body, p a `??` payload of `( vec_get [P] ps 0 )` with ps a local of the body: the copy-out rule skipped closure bodies (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( @ String ) f \ → String { : ( Vec P ) ps ( vec_new [P] ) ( vec_push [P] ps @ P { ( string_from `payload field string long enough` ) } ) ?? ( vec_get [P] ps 0 ) { T p → { ^ . p s } F → { ^ ( string_from `none` ) } } } ^ ( f ) }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
