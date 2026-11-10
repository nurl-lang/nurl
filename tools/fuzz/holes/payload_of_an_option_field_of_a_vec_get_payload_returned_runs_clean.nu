// payload_of_an_option_field_of_a_vec_get_payload_returned_runs_clean: `?? . r o { T e → { ^ e } … }` with r a `??` payload of `( vec_get [R] rs 0 )`, rs a local: the `__field__` pair's root r is a payload with no name on its slot, so e was taken for no lend.
// Closed (agora #560): the match uses the field path's root binding and the chain follows the `__field__` pair through r: e is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `?? . r o { T e → { ^ e } … }` with r a `??` payload of `( vec_get [R] rs 0 )`, rs a local: the `__field__` pair's root r is a payload with no name on its slot, so e was taken for no lend (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec R ) rs ( vec_new [R] ) ( vec_push [R] rs @ R { @ ?String { T ( string_from `option field string long enough` ) } } ) ?? ( vec_get [R] rs 0 ) { T r → { ?? . r o { T e → { ^ e } F → { ^ ( string_from `none` ) } } } F → { ^ ( string_from `none` ) } } }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
