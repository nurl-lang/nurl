// move_only_value_stored_ok.nu — move-only values stored into owners
// (agora #157): read through the owner, an owner's own new value built
// from its old one (`= d ( dyn Size @ Wrap { d } )`), each dropped once.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Res { ( Vec i ) buf }

% Drop Res {
    @ drop Res r → v {
        ( nurl_println `drop` )
        ( vec_free [i] . r buf )
    }
}

@ mkr → Res {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 7 )
    ^ @ Res { b }
}

: Box1 { Res r i pad }

% Size [T] {
    @ size T self → i
}

% Size Res { @ size Res r → i { ^ ( vec_len [i] . r buf ) } }

: Wrap { % Size inner }

% Size Wrap { @ size Wrap w → i { ^ + 1 ( size . w inner ) } }

@ main → i {
    : Res a ( mkr )
    : Box1 h @ Box1 { a 0 }
    ( nurl_println_int ( vec_len [i] . . h r buf ) )
    : ~ % Size d ( dyn Size ( mkr ) )
    = d ( dyn Size @ Wrap { d } )
    ( nurl_println_int ( size d ) )
    ^ 0
}
