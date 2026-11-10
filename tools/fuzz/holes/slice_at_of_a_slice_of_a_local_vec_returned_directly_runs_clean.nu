// slice_at_of_a_slice_of_a_local_vec_returned_directly_runs_clean: `^ ( slice_at [String] sl 0 )`, sl a slice bound from a local Vec: the call's argument is a view, so the lend was taken for none and the element went to the caller as its own while the Vec's drop freed it.
// Closed (agora #560): an argument that is itself a lend (a view bound from a call, a `??` payload) is followed down the chain to the local it views (mem_ret_local_lend): the element is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ ( slice_at [String] sl 0 )`, sl a slice bound from a local Vec: the call's argument is a view, so the lend was taken for none and the element went to the caller as its own while the Vec's drop freed it (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec String ) vs ( mkvs ) : ( Slice String ) sl ( slice_from_vec [String] vs ) ^ ( slice_at [String] sl 0 ) }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
