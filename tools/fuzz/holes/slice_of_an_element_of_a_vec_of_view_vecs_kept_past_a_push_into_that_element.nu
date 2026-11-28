// map: §2.10 | A2 | rejected | - | AGORA-1041: a Slice of `( vec_at [( Vec s )] vv 0 )`, an element that owns its buffer and holds views, kept past pushes into that element
// AGORA-1041: refused - a part handed to a call that owns its storage is read as reached through the container's element (`^vv`), whether or not it holds views; what it holds stays what it is (main 69902dc0: accepted, heap-use-after-free)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

@ main → i {
    : ( Vec ( Vec s ) ) vv ( vec_new [( Vec s )] )
    ( vec_push [( Vec s )] vv ( vec_new [s] ) )
    ( vec_push [s] ( vec_at [( Vec s )] vv 0 ) `one` )
    : ( Slice s ) e1 ( slice_from_vec [s] ( vec_at [( Vec s )] vv 0 ) )
    : ~ i k 0
    ~ < k 64 {
        ( vec_push [s] ( vec_at [( Vec s )] vv 0 ) `two` )
        = k + k 1
    }
    ( nurl_println ( slice_at [s] e1 0 ) )
    ^ 0
}
