// option_field_of_a_vec_get_payload_returned_runs_clean: `^ . r o` of a `??` payload r of `( vec_get [R] rs 0 )`, rs a local, o a `?String` field: the copy-out-of-the-local rule was for handle fields only.
// Closed (agora #560): a field that owns heap data but is no handle (an option, a struct) is copied where the payload was lent out of a local.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ . r o` of a `??` payload r of `( vec_get [R] rs 0 )`, rs a local, o a `?String` field: the copy-out-of-the-local rule was for handle fields only (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → ?String { : ( Vec R ) rs ( vec_new [R] ) ( vec_push [R] rs @ R { @ ?String { T ( string_from `option field string long enough` ) } } ) ?? ( vec_get [R] rs 0 ) { T r → { ^ . r o } F → { ^ @ ?String { F } } } }

@ main → i { ?? ( first ) { T r → { ( nurl_println ( string_data r ) ) } F → {} } ^ 0 }
