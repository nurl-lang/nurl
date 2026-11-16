// map: §2.10 | A2 | rejected | - | agora #811: a Vec of structs whose closure field captured an Rc share, handed to a callee that runs each to clear the payload
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/rc.nu`

: C { ( @ v ) run }

@ run_all ( Vec C ) cs → v {
    ~ c cs {
        : ( @ v ) f . c run
        ( f )
    }
}

@ main → i {
    : ( Vec String ) v0 ( vec_new [String] )
    ( vec_push [String] v0 ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) r ( rc_new [( Vec String )] v0 )
    : ( Rc ( Vec String ) ) r2 ( rc_clone [( Vec String )] r )
    : ( Vec C ) cs ( vec_new [C] )
    ( vec_push [C] cs @ C { \ → v { ( vec_clear [String] ( rc_get [( Vec String )] r ) ) } } )
    : ( Slice u ) sl ( string_bytes ( vec_at [String] ( rc_get [( Vec String )] r2 ) 0 ) )
    ( run_all cs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
