// nc_payload_moved_out_of_its_option.nu — a payload that cannot be copied
// (Pet holds a trait object), moved out of an option binding's `??` arm
// into a Vec: the arm is a cursor over the option, so the move takes the
// option's ownership along and the option releases nothing at its end. In a
// loop, after a `: ~` binding given another value on one path, out of an
// option of an option, and out of an option parameter. Before, the option
// released the payload the Vec held again: a double free.
$ `stdlib/core/vec.nu`

% Speaker [T] { @ speak T self → i }

: Dog { i pitch }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

: Pet { % Speaker s }

@ mk i k → Pet { ^ @ Pet { ( dyn Speaker @ Dog { k } ) } }

@ sum ( Vec Pet ) vs → i {
    : ~ i t 0
    ~ x vs { = t + t ( speak . x s ) }
    ^ t
}

: Holder { ? Pet o }

: | Zoo { Nada One Pet }

@ put ( Vec Pet ) vs ? Pet o → v { ?? o { T p → { ( vec_push [Pet] vs p ) } F → {} } }

@ main → i {
    : ( Vec Pet ) vs ( vec_new [Pet] )
    : ?Pet got @ ?Pet { T ( mk 3 ) }
    ?? got { T p → { ( vec_push [Pet] vs p ) } F → {} }
    : ~ i k 0
    ~ < k 4 {
        : ?Pet each ? == % k 2 0 @ ?Pet { T ( mk k ) } @ ?Pet { F }
        ?? each { T p → { ( vec_push [Pet] vs p ) } F → {} }
        = k + k 1
    }
    : ~ ? Pet some @ ?Pet { T ( mk 10 ) }
    ? > ( vec_len [Pet] vs ) 50 { = some @ ?Pet { F } } {}
    ?? some { T p → { ( vec_push [Pet] vs p ) } F → {} }
    : ?? Pet gg @ ?? Pet { T @ ?Pet { T ( mk 20 ) } }
    ?? gg { T g → { ?? g { T p → { ( vec_push [Pet] vs p ) } F → {} } } F → {} }
    ( put vs @ ?Pet { T ( mk 100 ) } )
    : ?Pet held @ ?Pet { T ( mk 200 ) }
    ( put vs held )
    : Holder h @ Holder { @ ?Pet { T ( mk 1000 ) } }
    : i hn ?? . h o { T p → ( speak . p s ) F → 0 }
    : Zoo z @ Zoo { One ( mk 2000 ) }
    : i zn ?? z { One p → ( speak . p s ) Nada → 0 }
    ( nurl_println_int + hn zn )
    ( nurl_println_int ( vec_len [Pet] vs ) )
    ( nurl_println_int ( sum vs ) )
    ^ 0
}
