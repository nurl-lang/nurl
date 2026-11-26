// A foreach whose body leaves a round early and leaves the loop.
$ `stdlib/core/vec.nu`

@ main → i {
    : ~ ( Vec i ) v ( vec_new [i] )
    ( vec_push [i] v 1 )
    ( vec_push [i] v 2 )
    ( vec_push [i] v 3 )
    : ~ i acc 0
    ~ x v {
        ? == x 2 { continue } {}
        ? > acc 10 { break } {}
        = acc + acc x
    }
    ^ acc
}
