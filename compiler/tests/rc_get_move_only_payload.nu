// rc_get_move_only_payload.nu — a value that cannot be copied (a struct
// with a `% Drop` field) read out of an Rc by rc_get is LENT: the binding
// borrows the Rc's own value. It was taken for owned and dropped at the
// end of the scope — the Rc's value dropped twice and an Rc it held let
// go one time too many (a use-after-free on main). The binding now takes
// the call's ownership answer, as a String or Vec binding does.
$ `stdlib/std/rc.nu`

: Res { i id }

% Drop Res { @ drop Res r → v { ( nurl_print `drop res ` ) ( nurl_print_int . r id ) ( nurl_print `\n` ) } }

: Node { Res r ? ( Rc Node ) next }

@ main → i {
    : ( Rc Node ) a ( rc_new [Node] @ Node { @ Res { 1 } @ ?( Rc Node ) { F } } )
    : ( Rc Node ) b ( rc_new [Node] @ Node { @ Res { 2 } @ ?( Rc Node ) { T ( rc_clone [Node] a ) } } )
    : Node nb ( rc_get [Node] b )
    ( rc_set [Node] b @ Node { @ Res { 3 } . nb next } )
    ( nurl_print `a strong: ` ) ( nurl_print_int ( rc_strong [Node] a ) ) ( nurl_print `\n` )
    ^ 0
}
