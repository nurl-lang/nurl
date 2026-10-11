// What a struct literal may still leave out: a field whose zero is a value
// of it — a number, a flag, an option (F), a raw string (empty), or a struct
// of those. An `unsafe` function may leave anything out and fill it in.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: Inner { i a f b }

: Rec { i n f x b on ? i maybe s name Inner inner ( Vec i ) items }

unsafe @ filled → Rec {
    : ~ Rec r @ Rec { 1 }
    = . r items ( vec_new [i] )
    ( vec_push [i] . r items 9 )
    ^ r
}

@ main → i {
    : Rec r @ Rec { 7 2.5 T @ ?i { F } `` @ Inner {} ( vec_new [i] ) }
    : Rec q @ Rec { 3 0.0 F @ ?i { T 4 } `x` @ Inner { 2 } ( vec_new [i] ) }
    ( nurl_println_int . r n )
    ( nurl_println_int . . r inner a )
    ( nurl_println_int ?? . q maybe { T v → v F → -1 } )
    ( nurl_println_int . . q inner a )
    : Rec z ( filled )
    ( nurl_println_int ( vec_len [i] . z items ) )
    ( nurl_println_int ?? . z maybe { T v → v F → -1 } )
    ^ 0
}
