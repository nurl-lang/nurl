// inout_param_given_a_field_of_a_lent_vec_element_runs_clean: `= dst . ( vec_at [App] xs 0 ) v`: a field of an element a call lends
// Closed: a field of a call's value is copied where the call lent it, by the call's bit, as `^ . ( f ) x` is (agora #697).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #697: `= dst . ( vec_at [App] xs 0 ) v`: a field of an element a call lends
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v String name ? String o i n }
: Out { App inner i k }
: G [T] { T v i n }

@ mka → App { : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ @ App { v ( string_from `an app name long enough for the heap buffer` ) @ ?String { T ( string_from `an option payload long enough for the heap` ) } 1 } }

@ r inout ( Vec i ) dst ( Vec App ) xs → v { = dst . ( vec_at [App] xs 0 ) v }

@ main → i {
    : ~ ( Vec App ) xs ( vec_new [App] ) ( vec_push [App] xs ( mka ) )
    : ~ ( Vec i ) c ( vec_new [i] )
    ( r c xs )
    ( vec_push [i] c 1 )
    ^ - ( vec_len [i] . ( vec_at [App] xs 0 ) v ) 1
}
