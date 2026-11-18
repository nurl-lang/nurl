// map: §2.10 | A2 | rejected | - | AGORA-842: `: v ?? o { T q → ( slice_from_vec q ) … }` over a local option, then `( grow o )` pushes into the payload
// AGORA-842: refused - a view of a `??` payload named past its arm points into the option it was read out of (`cuo_`) (main 34edc2a1: accepted, heap-use-after-free)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ grow inout ? ( Vec i ) o → v { ?? o { T q → { : ~ i k 0 ~ < k 1000 { ( vec_push [i] q k ) = k + k 1 } } F → {} } }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ( Vec i ) ys ( vec_new [i] )
    : ~ ? ( Vec i ) o @ ?( Vec i ) { T xs }
    : ( Slice i ) v ?? o { T q → ( slice_from_vec [i] q ) F → ( slice_from_vec [i] ys ) }
    ( grow o )
    ( nurl_println_int ( slice_at [i] v 1 ) )
    ^ 0
}
