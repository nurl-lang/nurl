// ret_lend_copy.nu — returning what a call lent out of a value this frame
// owns copies it, also when the callee is a generic instance compiled after
// the caller (the decision is a module-end constant), and a value read
// through a pointer is taken to lend from every parameter.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/core/box.nu`
$ `stdlib/std/rc.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ show s label i n → v { ( nurl_print label ) ( nurl_print `=` ) ( nurl_print ( nurl_str_int n ) ) ( nurl_print `\n` ) }

@ from_box → String {
    : ( Box String ) b ( box_new [String] ( string_from `bx` ) )
    ^ ( box_get [String] b )
}

@ from_rc → String {
    : ( Rc String ) a ( rc_new [String] ( string_from `rc` ) )
    ^ ( rc_get [String] a )
}

@ from_vec → String {
    : ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `vec` ) )
    ^ ?? ( vec_get [String] v 0 ) { T s → s F → ( string_from `` ) }
}

@ via_param ( Rc String ) a → String { ^ ( rc_get [String] a ) }

@ all → i {
    : String x ( from_box )
    : String y ( from_box )
    : String z ( from_rc )
    : String w ( from_vec )
    : ( Rc String ) a ( rc_new [String] ( string_from `pp` ) )
    : String q ( via_param a )
    ^ + + + ( string_len x ) ( string_len y ) + ( string_len z ) ( string_len w ) ( string_len q )
}

@ main → i {
    : i b0 ( live )
    ( show `total` ( all ) )
    ( show `left` - ( live ) b0 )
    ^ 0
}
