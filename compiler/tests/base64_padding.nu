// RFC 4648 padded and unpadded terminal groups, used by gRPC metadata.
$ `stdlib/std/encode.nu`

@ valid s input s expected → v {
    ?? ( b64_decode input ) {
        T value → {
            ? != ( nurl_str_eq ( string_data value ) expected ) 1 { ( nurl_exit 1 ) } {}
            ( string_free value )
        }
        F _ → ( nurl_exit 2 )
    }
}

@ invalid s input → v {
    ?? ( b64_decode input ) {
        T value → { ( string_free value ) ( nurl_print input ) ( nurl_exit 3 ) }
        F _ → {}
    }
}

@ main → i {
    ( valid `` `` )
    ( valid `Zg` `f` )
    ( valid `Zg==` `f` )
    ( valid `Zm8` `fo` )
    ( valid `Zm8=` `fo` )
    ( valid `Zm9v` `foo` )
    ( valid ` Z m 8 = \n` `fo` )
    ( invalid `A` )
    ( invalid `A=` )
    ( invalid `A==` )
    ( invalid `AA=` )
    ( invalid `AAA==` )
    ( invalid `AAAA=` )
    ( invalid `=` )
    ( invalid `==` )
    ( invalid `===` )
    ( invalid `Zg==A` )
    ( invalid `Zh` )
    ( invalid `Zm9` )
    ( nurl_print `base64 padding ok\n` )
    ^ 0
}
