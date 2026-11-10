// vec_get_payload_of_a_payload_returned: `^ e` of `?? ( vec_get [String]
// inner 0 ) { T e → … }` where inner is itself a payload of `( vec_get
// [( Vec String )] vv 0 )`, vv a local: the lend chain inner → vv was not
// followed, so e went to the caller as its own while vv's drop freed it.
// Closed (agora #553): a root that is itself a lend is followed to the local
// it was lent out of (__mem_payload_local_lend1), and e is taken out of its
// slot.
// main b997834: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | runs-clean | - | `^ e` of a vec_get payload of a vec_get payload of a local `( Vec ( Vec String ) )`: the lend chain was not followed, so the element went to the caller as its own and the local's drop freed it.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/option.nu`

@ first → String {
    : ( Vec ( Vec String ) ) vv ( vec_new [( Vec String )] )
    : ( Vec String ) in0 ( vec_new [String] )
    ( vec_push [String] in0 ( string_from `hello nested vec` ) )
    ( vec_push [( Vec String )] vv in0 )
    ?? ( vec_get [( Vec String )] vv 0 ) {
        T inner → {
            : ?String o ( vec_get [String] inner 0 )
            ?? o { T e → { ^ e } F → { ^ ( string_new ) } }
        }
        F → { ^ ( string_new ) }
    }
}

@ main → i {
    : String r ( first )
    ( nurl_println ( string_data r ) )
    ^ 0
}
