// map: §2.10 | A2 | rejected | - | AGORA-842: `= v ?? o { T q → ( slice_from_vec q ) … }` with o local to an inner block, v read after the block
// AGORA-842: refused - a view of a `??` payload named past its arm points into the option it was read out of (`cuo_`) (main 34edc2a1: accepted, heap-use-after-free)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec i ) d ( vec_new [i] )
    ( vec_push [i] d 7 )
    ( vec_push [i] d 8 )
    : ~ ( Slice i ) v ( slice_from_vec [i] d )
    ? == ( vec_len [i] d ) 2 {
        : ( Vec i ) xs ( vec_new [i] )
        : ~ i k 0
        ~ < k 64 { ( vec_push [i] xs k ) = k + k 1 }
        : ~ ? ( Vec i ) o @ ?( Vec i ) { T xs }
        = v ?? o { T q → ( slice_from_vec [i] q ) F → ( slice_from_vec [i] d ) }
    } {}
    ( nurl_println_int ( slice_at [i] v 1 ) )
    ^ 0
}
