// element_of_a_vec_pop_payload_returned_runs_clean: `?? ( vec_pop vv ) { T inner → ?? ( vec_get [String] inner 0 ) { T e → { ^ e } … } … }`: inner owns its value on the runs its flag says (`__sborrow` dyn), and a lend out of such a root was taken for none.
// Closed (agora #560): a lend out of a `dyn` root is one of this frame on the runs its drop flag is set, and follows what it was lent out of on the others: e is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `?? ( vec_pop vv ) { T inner → ?? ( vec_get [String] inner 0 ) { T e → { ^ e } … } … }`: inner owns its value on the runs its flag says (`__sborrow` dyn), and a lend out of such a root was taken for none (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] ) ( vec_push [( Vec String )] vv ( mkvs ) ) ?? ( vec_pop [( Vec String )] vv ) { T inner → { ?? ( vec_get [String] inner 0 ) { T e → { ^ e } F → { ^ ( string_from `none` ) } } } F → { ^ ( string_from `none` ) } } }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
