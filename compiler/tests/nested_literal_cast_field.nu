// nested_literal_cast_field.nu — a binding a nested literal reads is not
// the field of the literal around it.
//
// `^ @ H { # s ( rcbox_new [T] @ T { a b } ) }`: the outer field is a cast,
// and a cast field counted as "the binding it casts" — the last name parsed,
// `b`, inside the inner literal. The returned H then skipped `b`'s drop, and
// it leaked once per call (packages/vindex's VIndexImpl, wave-1 sweep).

$ `stdlib/core/vec.nu`
$ `stdlib/core/rcbox.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ report s what i d → v { ( nurl_print what ) ( nurl_print_int d ) ( nurl_print `\n` ) }

: PairImpl { ( Vec i ) v0 ( Vec i ) v1 }
: Pair { s ctl }

unsafe @ Pair_share Pair h → Pair { ^ @ Pair { # s ( rcbox_share # i . h ctl ) } }

@ Pair_drop sink Pair h → v { ( mem_forget h ) ( rcbox_release [PairImpl] # i . h ctl ) }

@ mk1 i x → ( Vec i ) { : ( Vec i ) v ( vec_new [i] ) ( vec_push [i] v x ) ^ v }

unsafe @ pair_of sink ( Vec i ) v0 sink ( Vec i ) v1 → Pair { ^ @ Pair { # s ( rcbox_new [PairImpl] @ PairImpl { v0 v1 } ) } }

unsafe @ pair_sum Pair p → i {
    : *PairImpl q ( rcbox_ptr [PairImpl] # i . p ctl )
    ^ + ?? ( vec_get [i] . q v0 0 ) { T x → x F → 0 } ?? ( vec_get [i] . q v1 0 ) { T x → x F → 0 }
}

@ round i k → i {
    : ( Vec i ) a ( mk1 k )
    : ( Vec i ) b ( mk1 1 )
    : Pair p ( pair_of a b )
    ^ ( pair_sum p )
}

@ main → i {
    : ~ i k 0
    : ~ i acc 0
    : ~ i l0 ( live )
    = k 0 ~ < k 20 { = acc + acc ( round k ) = k + k 1 }
    ( report `nested literal, last field a Vec: ` - ( live ) l0 )
    ( nurl_print_int acc ) ( nurl_print `\n` )
    ^ 0
}
