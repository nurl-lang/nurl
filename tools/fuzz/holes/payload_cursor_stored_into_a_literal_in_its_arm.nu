// map: §2.12 | A2 | rejected | - | AGORA-840: `?? o { T x → { : ~ cur x  : H q @ H { cur 0 } } }` - the literal takes the option's payload unseen, then o is read
// AGORA-840: refused - the store of a `: ~` copy of a `??` payload (or of a copy of one) takes the option's value, as `@ H { x 0 }` does (main fd008190: accepted, heap-use-after-free)
$ `stdlib/core/vec.nu`

: H { ( Vec i ) v i n }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    : ~ i k 0
    ~ < k 64 { ( vec_push [i] xs k ) = k + k 1 }
    : ~ ? ( Vec i ) o @ ?( Vec i ) { T xs }
    ?? o {
        T x → {
            : ~ ( Vec i ) cur x
            : H q @ H { cur 0 }
            ( nurl_println_int ( vec_len [i] . q v ) )
        }
        F → {}
    }
    ?? o { T x → ( nurl_println_int ( vec_at [i] x 1 ) ) F → {} }
    ^ 0
}
