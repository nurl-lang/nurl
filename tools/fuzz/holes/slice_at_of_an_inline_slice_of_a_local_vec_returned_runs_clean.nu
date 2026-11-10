// slice_at_of_an_inline_slice_of_a_local_vec_returned_runs_clean: `^ ( slice_at [String] ( slice_from_vec [String] vs ) 0 )`, vs a local: the inner call was an argument with no name, so what it lent out of vs was not followed.
// Closed (agora #560): a call argument that may lend out of a local stands as a name of its own (`__alr#N`, g_call_lroots) carrying that call's pairs: the element is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ ( slice_at [String] ( slice_from_vec [String] vs ) 0 )`, vs a local: the inner call was an argument with no name, so what it lent out of vs was not followed (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec String ) vs ( mkvs ) ^ ( slice_at [String] ( slice_from_vec [String] vs ) 0 ) }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
