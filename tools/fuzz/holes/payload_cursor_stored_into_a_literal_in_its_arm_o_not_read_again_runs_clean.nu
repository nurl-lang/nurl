// payload_cursor_stored_into_a_literal_in_its_arm_o_not_read_again_runs_clean: `?? o { T x → { : ~ cur x  : H q @ H { cur 0 } } }`, o never read again
// AGORA-840 guard: accepted - the literal takes the option's payload, freed once
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
            : H q @ H { cur 0 }
            ( nurl_println_int ( vec_len [i] . q v ) )
        }
        F → {}
    }
    ^ 0
}
