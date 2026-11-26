// A foreach over a Vec parameter that returns from inside its body.
$ `stdlib/core/vec.nu`

@ first_big ( Vec i ) v → i {
    ~ x v {
        ? > x 5 { ^ x } {}
    }
    ^ -1
}

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 3 )
    ( vec_push [i] v 9 )
    ^ ( first_big v )
}
