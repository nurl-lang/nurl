// payload_cursor_read_in_its_arm_then_the_option_read_runs_clean: `?? o { T x → { : ~ cur x  ( vec_len cur ) } }`, then o is read
// AGORA-840 guard: accepted - a cursor only read hands nothing over
// map: §2.12 | A2 | runs-clean | - | AGORA-840
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
            : i q ( vec_len [i] cur )
            ( nurl_println_int q )
        }
        F → {}
    }
    ?? o { T x → ( nurl_println_int ( vec_at [i] x 1 ) ) F → {} }
    ^ 0
}
