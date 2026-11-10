// element_of_an_inline_slice_of_a_local_vec_bound_then_returned_runs_clean: `: String e ( slice_at [String] ( slice_from_vec [String] vs ) 0 )  ^ e`, vs a local: the binding's pairs named no root for the inner call.
// Closed (agora #560): the inner call stands as `__alr#N` in the binding's roots (`__pljr`): e is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `: String e ( slice_at [String] ( slice_from_vec [String] vs ) 0 )  ^ e`, vs a local: the binding's pairs named no root for the inner call (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec String ) vs ( mkvs ) : String e ( slice_at [String] ( slice_from_vec [String] vs ) 0 ) ^ e }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
