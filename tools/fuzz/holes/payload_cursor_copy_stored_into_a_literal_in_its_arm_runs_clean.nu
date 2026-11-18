// payload_cursor_copy_stored_into_a_literal_in_its_arm_runs_clean: `?? o { T x → { : ~ cur x  : H q @ H { ( mem_dup cur ) 0 } } }`, then o is read
// AGORA-840 guard: accepted - the literal holds a copy; o keeps its payload
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
            : H q @ H { ( mem_dup cur ) 0 }
            ( nurl_println_int ( vec_len [i] . q v ) )
        }
        F → {}
    }
    ?? o { T x → ( nurl_println_int ( vec_at [i] x 1 ) ) F → {} }
    ^ 0
}
