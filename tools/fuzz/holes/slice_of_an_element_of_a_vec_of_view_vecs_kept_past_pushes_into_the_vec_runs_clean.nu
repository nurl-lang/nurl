// map: §2.10 | A2 | runs-clean | - | AGORA-1041: a Slice of an element of a `( Vec ( Vec s ) )` kept past pushes into the Vec itself, which move the elements' handles and not their buffers
// AGORA-1041's twin: the Slice points into element 0's buffer, reached through vv's element (`^vv`), as for a `( Vec ( Vec i ) )` (main 69902dc0 refused it: read as vv's own buffer)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    ( vec_push [s] ( vec_at [( Vec s )] vv 0 ) `one` )
    : ( Slice s ) e1 ( slice_from_vec [s] ( vec_at [( Vec s )] vv 0 ) )
    : ~ i k 0
    ~ < k 64 {
        ( vec_push [( Vec s )] vv ( vec_new [s] ) )
        = k + k 1
    }
    ( nurl_println ( slice_at [s] e1 0 ) )
    ^ 0
}
