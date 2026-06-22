// examples/distributed_map.nu — distributed map / word-count over the overlay
// (TODO §7.5 Phase 11, the keystone in action). A coordinator shards a corpus
// into chunks, each KEYED so dist/ring routes it to the worker that OWNS that
// key; the owning worker runs the registered word-count handler and returns
// the count; the coordinator awaits all and sums them. Real distributed
// computation — no central executor, work placed by consistent hashing,
// results flow back over net/transport and are recorded idempotently.
//
// Run as separate processes (a relay, two workers, one coordinator):
//
//   ./nurl.sh examples/relay.nu              0.0.0.0   47700
//   ./nurl.sh examples/distributed_map.nu    worker    127.0.0.1 47700 1
//   ./nurl.sh examples/distributed_map.nu    worker    127.0.0.1 47700 2
//   ./nurl.sh examples/distributed_map.nu    map       127.0.0.1 47700
//
// The coordinator prints the aggregate word count (expected 17).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/net/transport.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/dist/job.nu`

@ pk_for i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + id k ) = k + k 1 } ^ v }

@ key_for i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) ( vec_push [u] v # u & id 255 ) ( vec_push [u] v # u & >> id 8 255 ) ( vec_push [u] v # u 200 ) ( vec_push [u] v # u 7 ) ^ v }

@ chunk_text i id → String {
    ^ ? == id 0 ( string_from `the quick brown fox` )
    ? == id 1 ( string_from `jumps over the lazy dog` )
    ? == id 2 ( string_from `a b c d e` )
    ( string_from `one two three` )
}

@ str_bytes String s → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : s cs ( string_data s ) : i n ( string_len s ) : *u sp # *u cs
    : ~ i k 0 ~ < k n { ( vec_push [u] v # u . sp k ) = k + k 1 }
    ^ v
}

// word-count handler: payload = text bytes → result = 4-byte BE word count
@ wordcount_handler → ( @ ( Vec u ) ( Vec u ) ) {
    ^ \ ( Vec u ) p → ( Vec u ) {
        : i n ( vec_len [u] p )
        : ~ i words 0
        : ~ i in_word 0
        : ~ i k 0
        ~ < k n {
            : i ch ?? ( vec_get [u] p k ) { T x → # i x F → 32 }
            ? == ch 32 { = in_word 0 } { ? == in_word 0 { = words + words 1 = in_word 1 } {} }
            = k + k 1
        }
        : ( Vec u ) r ( vec_new [u] )
        ( bytes_push_u32_be r # u32 words )
        ^ r
    }
}

@ make_ring → *Ring {
    : *Ring r ( ring_new )
    : ( Vec u ) w0 ( pk_for 1 ) : ( Vec u ) w1 ( pk_for 2 )
    ( ring_add_member r w0 64 ) ( ring_add_member r w1 64 )
    ( vec_free [u] w0 ) ( vec_free [u] w1 )
    ^ r
}

@ run_worker s host i port i id → v {
    ?? ( relay_dial host port ) {
        T rc → {
            : ( Vec u ) me ( pk_for id )
            ?? ( relay_register rc me ) { T _ → {} F _ → {} }
            ( relay_set_timeout rc 250 )
            : *Transport tr # *Transport ( transport_open # s 0 rc 1 )
            : *Ring ring ( make_ring )
            : *JobNode jn ( job_node_new # s tr # s ring me id )
            ( job_register jn 0 ( wordcount_handler ) )
            ( nurl_print `worker ` ) ( nurl_print_int id ) ( nurl_print ` ready\n` )
            // blocking pump (recv honours the socket timeout outside fibers)
            : ~ i ticks 0
            ~ < ticks 40 { ( job_pump jn 200 ) = ticks + ticks 1 }
            ( job_node_free jn ) ( ring_free ring ) ( transport_free tr )
            ( vec_free [u] me ) ( relay_close rc )
        }
        F e → ( nurl_print `worker dial failed\n` )
    }
}

@ run_coordinator s host i port → v {
    ?? ( relay_dial host port ) {
        T rc → {
            : ( Vec u ) me ( pk_for 99 )
            ?? ( relay_register rc me ) { T _ → {} F _ → {} }
            ( relay_set_timeout rc 250 )
            : *Transport tr # *Transport ( transport_open # s 0 rc 1 )
            : *Ring ring ( make_ring )
            : *JobNode jn ( job_node_new # s tr # s ring me 99 )

            : ( Vec i ) tids ( vec_new [i] )
            : ~ i i 0
            ~ < i 4 {
                : ( Vec u ) key ( key_for i )
                : String txt ( chunk_text i )
                : ( Vec u ) payload ( str_bytes txt )
                ( vec_push [i] tids ( job_submit jn 0 key payload ) )
                ( vec_free [u] key ) ( string_free txt ) ( vec_free [u] payload )
                = i + i 1
            }

            // collect: pump until all four results land (or give up)
            : ~ i rounds 0
            : ~ b done F
            ~ & ! done < rounds 40 {
                ( job_pump jn 200 )
                : ~ b all T : ~ i j 0
                ~ < j 4 { ? ! ( job_has jn ?? ( vec_get [i] tids j ) { T x → x F → 0 } ) { = all F } {} = j + j 1 }
                = done all
                = rounds + rounds 1
            }

            : ~ i total 0
            : ~ i j 0
            ~ < j 4 {
                ?? ( job_await jn ?? ( vec_get [i] tids j ) { T x → x F → 0 } ) {
                    T r → { = total + total ?? ( bytes_read_u32_be r 0 ) { T x → # i x F → 0 } ( vec_free [u] r ) }
                    F → {}
                }
                = j + j 1
            }
            ( nurl_print `distributed word count total = ` ) ( nurl_print_int total ) ( nurl_print ` (expected 17)\n` )

            ( vec_free [i] tids )
            ( job_node_free jn ) ( ring_free ring ) ( transport_free tr )
            ( vec_free [u] me ) ( relay_close rc )
        }
        F e → ( nurl_print `coordinator dial failed\n` )
    }
}

@ main → i {
    : i argc ( env_args_count )
    ? < argc 3 { ( nurl_print `usage: distributed_map <worker|map> <host> <port> [id]\n` ) ^ 1 } {}
    : String role ( env_arg 1 )
    : String host ( env_arg 2 )
    : String ps ( env_arg 3 ) : i port ( nurl_str_to_int ( string_data ps ) ) ( string_free ps )

    ? != 0 ( nurl_str_eq ( string_data role ) `worker` ) {
        : i id ? > argc 4 { : String is ( env_arg 4 ) : i v ( nurl_str_to_int ( string_data is ) ) ( string_free is ) v } 1
        ( run_worker ( string_data host ) port id )
    } {
        ( run_coordinator ( string_data host ) port )
    }
    ( string_free role ) ( string_free host )
    ^ 0
}
