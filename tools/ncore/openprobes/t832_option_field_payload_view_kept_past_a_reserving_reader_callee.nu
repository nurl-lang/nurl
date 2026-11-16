// map: §2.10 | A2 | rejected | - | agora #832: `?? . h o { T q → … ( w . h o ) … }` - a plain-parameter callee reserving the field option's payload while a slice of it lives
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: Hh { ? ( Vec i ) o i n }

@ w ? ( Vec i ) o → v { ?? o { T p → ( vec_reserve [i] p 4096 ) F → {} } }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 1 )
    ( vec_push [i] xs 2 )
    : Hh h @ Hh { @ ?( Vec i ) { T xs } 0 }
    ?? . h o {
        T q → {
            : ( Slice i ) sl ( slice_from_vec [i] q )
            ( w . h o )
            ( nurl_println_int ( slice_at [i] sl 1 ) )
        }
        F → {}
    }
    ^ 0
}
