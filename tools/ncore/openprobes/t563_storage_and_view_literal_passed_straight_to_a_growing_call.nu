// map: §2.10 | A2 | rejected | - | agora #563: `( use @ S { sv b } )` - a literal of a storage field and a view of it handed straight to a call that grows the storage
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: S { ( Slice i ) v ( Vec i ) buf }

@ use sink S x → v {
    : ~ S y x
    : ~ i k 0
    ~ < k 1000 { ( vec_push [i] . y buf k ) = k + k 1 }
    ( nurl_println_int ( slice_at [i] . y v 1 ) )
}

@ main → i {
    : ( Vec i ) b ( vec_new [i] )
    ( vec_push [i] b 1 )
    ( vec_push [i] b 2 )
    : ( Slice i ) sv ( slice_from_vec [i] b )
    ( use @ S { sv b } )
    ^ 0
}
