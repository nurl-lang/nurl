// map: §2.10 | A2 | rejected | - | agora #811: a struct nesting a struct whose closure field captured an Rc share, handed to a callee that runs it to clear the payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: C { ( @ v ) run }
: O { C c i n }

@ go O o → v {
    : ( @ v ) f . . o c run
    ( f )
}

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : O o @ O { @ C { \ → v { ( vec_clear [String] ( rc_get [( Vec String )] r ) ) } } 1 }
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( go o )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
