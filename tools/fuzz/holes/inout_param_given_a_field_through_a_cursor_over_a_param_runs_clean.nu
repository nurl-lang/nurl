// inout_param_given_a_field_through_a_cursor_over_a_param_runs_clean: `: App y x  = dst . y name`: the field read through a cursor over a borrowed parameter
// Closed: a field read of a binding is a lend of its owner: stored into an `inout` place it is copied there, the old value going, as `= io . w s` of a local already was (agora #697).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.12 | A2 | runs-clean | - | agora #697: `: App y x  = dst . y name`: the field read through a cursor over a borrowed parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v String name ? String o i n }
: Out { App inner i k }
: G [T] { T v i n }

@ mka → App { : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ @ App { v ( string_from `an app name long enough for the heap buffer` ) @ ?String { T ( string_from `an option payload long enough for the heap` ) } 1 } }

@ r inout String dst App x → v { : App y x = dst . y name }

@ main → i {
    : App a ( mka )
    : ~ String c ( string_from `old value, long enough for the heap buffer` )
    ( r c a )
    ^ - ( string_len c ) ( string_len . a name )
}
