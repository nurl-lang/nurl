// nested_field_of_a_vec_get_payload_returned_runs_clean: `^ . . p q s` of a `??` payload p of `( vec_get [Q] ps 0 )`, ps a local: gen_ret peeked the root only after a single `.`.
// Closed (agora #560): the root of a nested field path is the binding the field read recorded (`__last_member_root__`): the field is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ . . p q s` of a `??` payload p of `( vec_get [Q] ps 0 )`, ps a local: gen_ret peeked the root only after a single `.` (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec Q ) ps ( vec_new [Q] ) ( vec_push [Q] ps @ Q { @ P { ( string_from `nested field string long enough` ) } } ) ?? ( vec_get [Q] ps 0 ) { T p → { ^ . . p q s } F → { ^ ( string_from `none` ) } } }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
