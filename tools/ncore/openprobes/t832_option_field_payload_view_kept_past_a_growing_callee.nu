// map: §2.10 | A2 | rejected | - | agora #832: `?? . h o { T q → … ( w . h o ) … }` - a view of the payload outlives a callee growing it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Hh { ? ( Vec i ) o }

@ w inout ? ( Vec i ) o → v {
    ?? o { T q → { : ~ i j 0 ~ < j 64 { ( vec_push [i] q j ) = j + j 1 } } F → {} }
}

@ main → i {
    : ~ Hh h @ Hh { @ ?( Vec i ) { T ( vec_new [i] ) } }
    ?? . h o {
        T q → {
            ( vec_push [i] q 65 )
            : ( Slice i ) sl ( slice_from_vec [i] q )
            ( w . h o )
            ( nurl_println_int ( slice_at [i] sl 0 ) )
        }
        F → {}
    }
    ^ 0
}
