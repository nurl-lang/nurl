// The other ways to a zero value that is not a value of its type, each
// rejected outside `unsafe` (h183–h188). Every function is checked on its
// own, so one compile reports them all.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/rc.nu`

: | Shape { Dot Poly ( Vec i ) }

: Bag { i n ( Vec i ) items }

@ enum_payload_left_out → i {
    : Shape s @ Shape { Poly }
    ^ 0
}

@ option_tag_only → i {
    : ?( Vec i ) o @ ?( Vec i ) { T }
    ^ 0
}

@ result_tag_only → i {
    : !i String r @ !i String { F }
    ^ 0
}

@ bare_variant_with_payload → i {
    : Shape s Poly
    ^ 0
}

@ bare_variant_in_join b c → i {
    : Shape s ? c Poly Dot
    ^ 0
}

@ zeroed_vec_of_vecs → i {
    : ( Vec ( Vec i ) ) vv ( vec_zeroed [( Vec i )] 2 )
    ^ 0
}

@ zeroed_rc_of_string → i {
    : ( Rc String ) r ( rc_zero [String] )
    ^ 0
}

@ number_into_vec → i {
    : ( Vec i ) v 0
    ^ 0
}

@ number_into_vec_field → i {
    : Bag b @ Bag { 1 0 }
    ^ 0
}

@ take_vec ( Vec i ) v → i { ^ ( vec_len [i] v ) }

@ number_as_vec_argument → i {
    ^ ( take_vec 0 )
}

@ main → i { ^ 0 }
