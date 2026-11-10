// element_of_a_payload_of_a_local_option_vec_returned_runs_clean: `: ?( Vec String ) ov ( vec_pop vv )  ?? ov { T inner → ?? ( vec_get [String] inner 0 ) { T e → { ^ e } … } … }`: inner is a cursor over ov, and what is lent out of it was not asked of ov.
// Closed (agora #560): a lend out of a cursor root is one out of the binding it is a cursor over (`__plbind`), wherever that one's drop is still due: e is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `: ?( Vec String ) ov ( vec_pop vv )  ?? ov { T inner → ?? ( vec_get [String] inner 0 ) { T e → { ^ e } … } … }`: inner is a cursor over ov, and what is lent out of it was not asked of ov (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] ) ( vec_push [( Vec String )] vv ( mkvs ) ) : ?( Vec String ) ov ( vec_pop [( Vec String )] vv ) ?? ov { T inner → { ?? ( vec_get [String] inner 0 ) { T e → { ^ e } F → { ^ ( string_from `none` ) } } } F → { ^ ( string_from `none` ) } } }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
