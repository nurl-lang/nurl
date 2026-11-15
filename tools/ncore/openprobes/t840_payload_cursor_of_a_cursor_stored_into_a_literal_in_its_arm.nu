// map: §2.12 | A2 | rejected | - | agora #840: `?? o { T x → { : ~ c1 x  : ~ c2 c1  : H q @ H { c2 0 } } }` - a cursor of a cursor of the payload stored, then o is read
$ `stdlib/core/vec.nu`

: H { ( Vec i ) v i n }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [i] xs k ) = k + k 1 }
    : ~ ?( Vec i ) o @ ?( Vec i ) { T xs }
    ?? o {
        T x → {
            : ~ ( Vec i ) c1 x
            : ~ ( Vec i ) c2 c1
            : H q @ H { c2 0 }
            ( nurl_println_int ( vec_len [i] . q v ) )
        }
        F → {}
    }
    ?? o { T x → ( nurl_println_int ( vec_at [i] x 1 ) ) F → {} }
    ^ 0
}
