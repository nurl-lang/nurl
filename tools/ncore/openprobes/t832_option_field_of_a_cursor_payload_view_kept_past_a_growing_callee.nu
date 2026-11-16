// map: §2.10 | A2 | rejected | - | agora #832: `: ~ Hh c h  ?? . c o { T q → … ( w . c o ) … }` - a cursor's option field payload viewed past a callee growing it (#842 item 4)
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Hh { ? ( Vec i ) o i n }

@ w inout ? ( Vec i ) o → v {
    ?? o { T q → { : ~ i j 0 ~ < j 1000 { ( vec_push [i] q j ) = j + j 1 } } F → {} }
}

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : ~ Hh h @ Hh { @ ?( Vec i ) { T xs } 0 }
    : ~ Hh c h
    ?? . c o {
        T q → {
            : ( Slice i ) sl ( slice_from_vec [i] q )
            ( w . c o )
            ( nurl_println_int ( slice_at [i] sl 1 ) )
        }
        F → {}
    }
    ^ 0
}
