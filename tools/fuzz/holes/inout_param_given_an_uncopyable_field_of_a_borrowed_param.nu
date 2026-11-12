// inout_param_given_an_uncopyable_field_of_a_borrowed_param: `= dst . x b` with b a `% Drop` field with no clone, of a by-value parameter
// Closed: the field would need a copy, and it has none: refused where it is read (agora #697).
// main ae5e524: accepted; AddressSanitizer: heap-use-after-free (both ran the destructor).
// map: §2.12 | A2 | rejected | - | agora #697: `= dst . x b` with b a `% Drop` field with no clone, of a by-value parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: App { ( Vec i ) v String name ? String o i n }

@ mka → App { : ~ ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v 7 ) ^ @ App { v ( string_from `an app name long enough for the heap buffer` ) @ ?String { T ( string_from `an option payload long enough for the heap` ) } 1 } }

: Bomb { String tag }

% Drop Bomb { @ drop Bomb b → v { ( nurl_println ( string_data . b tag ) ) } }

: H { Bomb b i n }

@ r inout Bomb dst H x → v { = dst . x b }

@ main → i {
    : H h @ H { @ Bomb { ( string_from `inner bomb` ) } 1 }
    : ~ Bomb c @ Bomb { ( string_from `outer bomb` ) }
    ( r c h )
    ^ 0
}
