// map: §7.6 | A2 | runs-clean | - | agora #841: `( vec_push [Q] v @ Q { [i | 1 2] 2 } )`, Q `{ [i xs i n }`: a Vec's element release does not free the element's slice
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Q { [i xs i n }

@ main → i {
    : ~ ( Vec Q ) v ( vec_new [Q] )
    ( vec_push [Q] v @ Q { [i | 1 2] 2 } )
    ( nurl_println_int ( vec_len [Q] v ) )
    ^ 0
}
