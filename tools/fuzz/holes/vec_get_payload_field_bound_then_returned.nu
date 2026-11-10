// vec_get_payload_field_bound_then_returned: `?? ( vec_get [P] ps 13 ) { T p → {
// : String t . p s  ^ t } … }`, ps a local: t, a field read of the payload, had no
// lend pairs, so `^ t` handed the caller the element's String while ps's drop
// freed it. Closed (agora #560): a field read binds the pairs of the binding
// it is a field of, so t is copied as `^ . p s` is.
// map: §7.6 | A2 | runs-clean | - | `^ t` of `: String t . p s`, p a vec_get payload of a local: the field went to the caller as its own and the local's drop freed it (agora #560).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/option.nu`
$ `stdlib/std/panic.nu`

: P { String s i n }

@ first → String {
    : ( Vec P ) ps ( vec_new [P] )
    : ~ i k 0
    ~ < k 20 { ( vec_push [P] ps @ P { ( string_from `many` ) k } ) = k + k 1 }
    ?? ( vec_get [P] ps 13 ) { T p → { : String t . p s ^ t } F → { ^ ( string_new ) } }
}

@ main → i { : String r ( first ) ( nurl_println ( string_data r ) ) ^ 0 }
