// An Rc held in the payload of an Rc is reached through it: clearing the
// inner payload through a value lent out of the outer one ends the views
// taken through another share of the inner Rc (agora #592).
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: Impl { ( Vec String ) items ( Rc ( Vec String ) ) side }
: RI { ( Rc Impl ) a }

@ main → i {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `an element string long enough for a heap buffer` ) )
    : ( Rc ( Vec String ) ) rs ( rc_new [( Vec String )] v )
    : ( Rc ( Vec String ) ) rs2 ( rc_clone [( Vec String )] rs )
    : ~ RI h @ RI { ( rc_new [Impl] @ Impl { ( vec_new [String] ) rs } ) }
    : String e ( vec_at [String] ( rc_get [( Vec String )] rs2 ) 0 )
    : Impl ca ( rc_get [Impl] . h a )
    : ( Vec String ) sv ( rc_get [( Vec String )] . ca side )
    ( vec_clear [String] sv )
    ( nurl_println ( string_data e ) )
    ^ 0
}
