// element_of_an_aliased_slice_of_a_local_vec_returned_runs_clean: `: ( Slice String ) s2 sl  : String e ( slice_at [String] s2 0 )  ^ e`: a slice bound from another slice kept no record of what it views.
// Closed (agora #560): `__note_view_lend` gives s2 the pairs of sl: e is copied.
// main 00e8da6: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `: ( Slice String ) s2 sl  : String e ( slice_at [String] s2 0 )  ^ e`: a slice bound from another slice kept no record of what it views (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`

: P { String s }
: R { ? String o }
: Q { P q }
: PP { Q p }

@ mkvs → ( Vec String ) { : ( Vec String ) vs ( vec_new [String] ) ( vec_push [String] vs ( string_from `hello world slice element number zero` ) ) ( vec_push [String] vs ( string_from `hello world slice element number one` ) ) ^ vs }

@ first → String { : ( Vec String ) vs ( mkvs ) : ( Slice String ) sl ( slice_from_vec [String] vs ) : ( Slice String ) s2 sl : String e ( slice_at [String] s2 0 ) ^ e }

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
