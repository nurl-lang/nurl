// vec_get_payload_field_returned: `?? ( vec_get [P] ps 0 ) { T p → { ^ . p s
// } … }`, ps a local `( Vec P )`: the field went to the caller as its own and
// was neither taken out of the slot nor copied, so ps's drop freed it.
// Closed (agora #553): the field is taken out of the Vec slot that holds it
// (mem_vget_field_consume), or copied where the slot is no longer known.
// main b997834: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ . p s` of a vec_get payload p of a local `( Vec P )`: the field was neither taken out of its slot nor copied, so the Vec's drop freed it under the caller.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

: P { String s i n }

@ first → String {
    : ( Vec P ) ps ( vec_new [P] )
    ( vec_push [P] ps @ P { ( string_from `hello world payload` ) 1 } )
    ?? ( vec_get [P] ps 0 ) {
        T p → { ^ . p s }
        F → { ^ ( string_new ) }
    }
}

@ main → i {
    : String r ( first )
    ( nurl_println ( string_data r ) )
    ^ 0
}
