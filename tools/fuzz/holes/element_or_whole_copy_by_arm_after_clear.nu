// element_or_whole_copy_by_arm_after_clear: agora #118 — `x` is an element of `o.kids` on one arm and a copy of `o` itself on the other (`? c { = x ( vec_at [N] . o kids 0 ) } { = x ( idn o ) }`), then `( vec_clear [N] . o kids )` and a read through `x`. The copy of `o` survives the clear; the element does not, and after the join `x` may be either (element_or_whole_copy_by_arm_after_clear).
// Pin: what a borrow is a copy of keeps, across a binding's values, the answer that ends it (bck_br_set): the arm walked last does not decide for the other.
// main: rejected (every borrow of the vector's owner ended on a clear).
// map: §2.10 | A1 | rejected | - | agora #118: a binding that is an element on one arm and a whole copy on the other, read after the elements were cleared
$ `stdlib/core/vec.nu`

: N { ( Vec N ) kids i v }

@ idn N x → N { ^ x }

@ main → i {
    : ( Vec N ) ks ( vec_new [N] )
    ( vec_push [N] ks @ N { ( vec_new [N] ) 1 } )
    : N o @ N { ks 2 }
    : ~ N x ( idn o )
    ? == . o v 2 { = x ( vec_at [N] . o kids 0 ) } { = x ( idn o ) }
    ( vec_clear [N] . o kids )
    ( nurl_println_int ( vec_len [N] . x kids ) )
    ^ 0
}
