// A value handed out of a block through a binding the block declared
// borrows what that binding held (h216). `v` is `t`, and `t` is an
// element of `outer`; the block's names end with it, so the value used
// to borrow nothing and outlived `outer`. Also through a `?` arm, an
// assignment in a nested block, and a chain of the block's own names —
// and the frozen-payload rule sees the same (an Arc view bound in a
// block and handed out).
$ `stdlib/core/vec.nu`
$ `stdlib/std/arc.nu`

@ tail ( Vec ( Vec i ) ) o0 → i {
    : ( Vec ( Vec i ) ) outer ( vec_clone [( Vec i )] o0 )
    : ( Vec i ) v { : ( Vec i ) t ( vec_at [( Vec i )] outer 0 ) t }
    ( vec_free [( Vec i )] outer )
    ^ ( vec_len [i] v )
}

@ arm ( Vec ( Vec i ) ) o0 b c → i {
    : ( Vec ( Vec i ) ) outer ( vec_clone [( Vec i )] o0 )
    : ( Vec i ) v ? c { : ( Vec i ) t ( vec_at [( Vec i )] outer 0 ) t } ( vec_new [i] )
    ( vec_free [( Vec i )] outer )
    ^ ( vec_len [i] v )
}

@ nested_assign ( Vec ( Vec i ) ) o0 b c → i {
    : ( Vec ( Vec i ) ) outer ( vec_clone [( Vec i )] o0 )
    : ( Vec i ) v { : ~ ( Vec i ) t ( vec_new [i] ) ? c { = t ( vec_at [( Vec i )] outer 0 ) } {} t }
    ( vec_free [( Vec i )] outer )
    ^ ( vec_len [i] v )
}

@ chain ( Vec ( Vec i ) ) o0 → i {
    : ( Vec ( Vec i ) ) outer ( vec_clone [( Vec i )] o0 )
    : ( Vec i ) v { : ( Vec i ) t ( vec_at [( Vec i )] outer 0 ) : ( Vec i ) u t u }
    ( vec_free [( Vec i )] outer )
    ^ ( vec_len [i] v )
}

@ frozen ( Arc ( Vec i ) ) a → v {
    : ( Vec i ) v { : ( Vec i ) t ( arc_get [( Vec i )] a ) t }
    ( vec_push [i] v 1 )
}

@ main → i { ^ 0 }
