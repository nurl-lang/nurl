// H647: agora #155 — enums with result payloads in a Vec, matched through vec_get (enum_result_payload_read_from_a_vec).
// Closed: an anonymous-aggregate payload is heap-boxed and owned by the enum, its closure env adopted or copied (enum_payload_storage 3, __enum_box_payload; agora #155).
// v0.80.0: accepted; LeakSanitizer.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: | E {
    Res ! String i
    NoVal
}

@ mk → String { ^ ( string_from `hello world, long enough for a heap buffer` ) }

@ main → i {
    : ( Vec E ) v ( vec_new [E] )
    ( vec_push [E] v @ E { Res @ !String i { T ( mk ) } } )
    ( vec_push [E] v @ E { Res @ !String i { F 7 } } )
    ( vec_push [E] v @ E { NoVal } )
    : ~ i n 0
    ~ < n ( vec_len [E] v ) {
        ?? ( vec_get [E] v n ) {
            T e → {
                ?? e {
                    Res r → { ?? r { T s → { ( nurl_println ( string_data s ) ) } F x → { ( nurl_println_int x ) } } }
                    NoVal → { ( nurl_println `none` ) }
                }
            }
            F → {}
        }
        = n + n 1
    }
    ^ 0
}
