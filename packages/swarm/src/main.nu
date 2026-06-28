// packages/swarm/src/main.nu — swarm: a distributed compute cluster you join by
// installing it.
//
//   nurlpkg install swarm           # drops the `swarm` binary on $PATH
//   swarm relay   0.0.0.0 47700     # the meeting point (one per cluster)
//   swarm worker  <host> <port>     # join as a compute node — that's the join
//   swarm submit  <host> <port> primes 1 1000000     # place a real workload
//
// A worker needs no recompile and no member list: it announces itself over the
// relay group, every node folds it into the consistent-hash ring (census.nu),
// and from then on it owns its share of the keyspace and runs the registered
// handlers (work.nu). The coordinator discovers the live workers the same way,
// shards a real numeric range across them by key (dist/ring → dist/job), and
// sums the partial results. Add a worker → it takes load on the next submit.
//
// Built entirely on the standard distributed stack: net/relay (reach),
// net/transport (the pubkey seam), dist/ring (ownership), dist/job (dispatch).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/random.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/net/transport.nu`
$ `stdlib/dist/ring.nu`
$ `stdlib/dist/job.nu`
$ `census.nu`
$ `work.nu`

@ swarm_vnodes → i { ^ 64 }

// The relay multicast group every node joins. It is a fixed 32 bytes on
// purpose: the relay's documented group-id contract is 32 bytes, and a 32-byte
// id round-trips correctly under every shipped relay framing — so a worker
// built against any toolchain release still finds the cluster. ("swarm" + zero
// padding keeps it recognisable on the wire.)
@ swarm_group_id → ( Vec u ) {
    : ( Vec u ) g ( bytes_from_str `swarm` )
    ~ < ( vec_len [u] g ) 32 { ( vec_push [u] g # u 0 ) }
    ^ g
}

// A 32-byte opaque routing pubkey derived deterministically from a node id.
// Over the relay leg the pubkey is just the address the relay forwards by, so a
// spread-out deterministic value is all the routing needs (the real X25519
// identity belongs to the direct securedgram leg, not used here).
@ pk_from_id i id → ( Vec u ) {
    : ( Vec u ) v ( vec_new [u] )
    : ~ i s id
    : ~ i k 0
    ~ < k 32 {
        = s + + * s 1103515245 12345 k
        ( vec_push [u] v # u & >> s 16 255 )
        = k + k 1
    }
    ^ v
}

// ── node bundle ───────────────────────────────────────────────────

: Swarm {
    s transport  // *Transport
    s ring  // *Ring
    s roster  // *Roster
    s job  // *JobNode
    ( Vec u ) self_pk
    i self_id
    i role
    ( Vec u ) group
}

@ swarm_new RelayClient rc i id i role → *Swarm {
    : ( Vec u ) me ( pk_from_id id )
    : *Transport tr # *Transport ( transport_open # s 0 rc 1 )
    : *Ring ring ( ring_new )
    : *Roster roster ( roster_new )
    : *JobNode jn ( job_node_new # s tr # s ring me id )
    : *Swarm sw # *Swarm ( nurl_alloc Z Swarm )
    = . sw transport # s tr
    = . sw ring # s ring
    = . sw roster # s roster
    = . sw job # s jn
    = . sw self_pk me
    = . sw self_id id
    = . sw role role
    = . sw group ( swarm_group_id )
    // A worker is itself a ring member; the coordinator (client) never is.
    ? == role ( role_worker ) { ( roster_add roster ring me id ( swarm_vnodes ) ) } {}
    ^ sw
}

@ swarm_free * Swarm sw → v {
    ( job_node_free # *JobNode . sw job )
    ( ring_free # *Ring . sw ring )
    ( roster_free # *Roster . sw roster )
    ( transport_free # *Transport . sw transport )
    ( vec_free [u] . sw self_pk )
    ( vec_free [u] . sw group )
    ( nurl_free # s sw )
}

@ swarm_join_group * Swarm sw → v {
    ?? ( transport_group_join # *Transport . sw transport . sw group ) { T _ → {} F _ → {} }
}

// Announce ourselves to the group. `want` asks hearers to reply so a newcomer
// learns the existing members.
@ swarm_announce * Swarm sw i want → v {
    : ( Vec u ) msg ( hello_build . sw self_id . sw role want . sw self_pk )
    ?? ( transport_broadcast # *Transport . sw transport . sw group msg ) { T _ → {} F _ → {} }
    ( vec_free [u] msg )
}

@ swarm_on_hello * Swarm sw Hello h → v {
    // Only workers join the ring; a client announcing itself is reachable but
    // owns no keys.
    ? == . h role ( role_worker ) {
        ( roster_add # *Roster . sw roster # *Ring . sw ring . h pubkey . h id ( swarm_vnodes ) )
        ( transport_add_peer # *Transport . sw transport . h pubkey )
    } {}
    // Reply to a discovery request unless it is our own broadcast echoed back.
    ? & == . h want 1 ! ( bytes_eq . h pubkey . sw self_pk ) {
        : ( Vec u ) reply ( hello_build . sw self_id . sw role 0 . sw self_pk )
        ?? ( transport_send # *Transport . sw transport . h pubkey reply ) { T _ → {} F _ → {} }
        ( vec_free [u] reply )
    } {}
}

// Drain inbound transport messages, dispatching census HELLO and job traffic.
@ swarm_pump * Swarm sw i max → v {
    : ~ b more T
    ~ more {
        ?? ( transport_recv # *Transport . sw transport max ) {
            T tm → {
                : i b0 ?? ( vec_get [u] . tm payload 0 ) { T x → # i x F → 255 }
                ? == b0 ( census_hello_t ) {
                    : Hello h ( hello_decode . tm payload )
                    ( swarm_on_hello sw h )
                    ( hello_free h )
                } {
                    : JobMsg m ( jobmsg_decode . tm payload )
                    ? == . m mtype ( job_submit_t ) { ( job_on_submit # *JobNode . sw job m ) } {}
                    ? == . m mtype ( job_result_t ) { ( job_on_result # *JobNode . sw job m ) } {}
                    ( jobmsg_free m )
                }
                ( transport_msg_free tm )
            }
            F → { = more F }
        }
    }
}

// ── roles ─────────────────────────────────────────────────────────

@ run_relay s host i port i vflag → i {
    ?? ( relay_server_start host port ) {
        T rs → {
            : *RelayServer p # *RelayServer ( nurl_alloc Z RelayServer )
            = . p lst . rs lst
            = . p clients . rs clients
            = . p groups . rs groups
            // `vflag` (not `verbose`): a store LHS `. p verbose` whose value-name
            // also matched the field would be parsed as an array-index store.
            = . p verbose vflag
            ( nurl_print `swarm relay listening on ` ) ( nurl_print host )
            ( nurl_print `:` ) ( nurl_print_int port )
            ? == vflag 1 { ( nurl_print ` (verbose: logging peer connect/disconnect)` ) } {}
            ( nurl_print `\n` )
            ( relay_server_run p )
            ( relay_server_free p )
            ^ 0
        }
        F e → { ( nurl_print `swarm: relay failed to bind\n` ) ^ 1 }
    }
}

@ swarm_register_handlers * Swarm sw → v {
    ( job_register # *JobNode . sw job ( kind_primes ) ( primes_handler ) )
    ( job_register # *JobNode . sw job ( kind_sumsq ) ( sumsq_handler ) )
}

@ run_worker s host i port i id i rounds → i {
    ?? ( relay_dial host port ) {
        T rc → {
            : ( Vec u ) reg ( pk_from_id id )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( vec_free [u] reg )
            ( relay_set_timeout rc 250 )
            : *Swarm sw ( swarm_new rc id ( role_worker ) )
            ( swarm_register_handlers sw )
            ( swarm_join_group sw )
            ( swarm_announce sw 1 )  // "I'm here — existing members, identify yourselves"
            ( nurl_print `swarm worker ` ) ( nurl_print_int id ) ( nurl_print ` ready (` )
            ( nurl_print_int ( roster_count # *Roster . sw roster ) ) ( nurl_print ` known)\n` )
            // Daemon loop. rounds<=0 means run until killed.
            : ~ i t 0
            ~ | <= rounds 0 < t rounds { ( swarm_pump sw 200 ) = t + t 1 }
            ( swarm_free sw )
            ( relay_close rc )
            ^ 0
        }
        F e → { ( nurl_print `swarm: worker could not dial relay\n` ) ^ 1 }
    }
}

// Discover the live workers: announce, then pump a short window collecting the
// HELLO replies that fold workers into the ring.
@ swarm_discover * Swarm sw i rounds → v {
    ( swarm_announce sw 1 )
    : ~ i t 0
    ~ < t rounds { ( swarm_pump sw 200 ) = t + t 1 }
}

@ run_submit s host i port i kind i lo i hi → i {
    ?? ( relay_dial host port ) {
        T rc → {
            : i myid ( rand_u64 )
            : ( Vec u ) reg ( pk_from_id myid )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( vec_free [u] reg )
            ( relay_set_timeout rc 250 )
            : *Swarm sw ( swarm_new rc myid ( role_client ) )
            ( swarm_join_group sw )
            ( swarm_discover sw 8 )

            : i nworkers ( roster_count # *Roster . sw roster )
            ? == nworkers 0 {
                ( nurl_print `swarm: no workers found — start some with 'swarm worker'\n` )
                ( swarm_free sw ) ( relay_close rc )
                ^ 1
            } {}

            : i nchunks ? > * nworkers 4 256 256 * nworkers 4
            ( nurl_print `swarm: ` ) ( nurl_print_int nworkers ) ( nurl_print ` worker(s), ` )
            ( nurl_print_int nchunks ) ( nurl_print ` chunk(s)\n` )

            : ( Vec s ) chunks ( shard lo hi nchunks )
            : ( Vec i ) tids ( vec_new [i] )
            : ~ i i 0
            ~ < i nchunks {
                : s cp ?? ( vec_get [s] chunks i ) { T x → x F → # s 0 }
                : *Chunk c # *Chunk cp
                : ( Vec u ) key ( chunk_key i )
                : ( Vec u ) payload ( chunk_payload . c lo . c hi )
                ( vec_push [i] tids ( job_submit # *JobNode . sw job kind key payload ) )
                ( vec_free [u] key ) ( vec_free [u] payload )
                = i + i 1
            }

            // Collect until every task has landed or we give up.
            : ~ i rnd 0
            : ~ b done F
            ~ & ! done < rnd 400 {
                ( swarm_pump sw 200 )
                : ~ b all T : ~ i j 0
                ~ < j nchunks {
                    ? ! ( job_has # *JobNode . sw job ?? ( vec_get [i] tids j ) { T x → x F → 0 } ) { = all F } {}
                    = j + j 1
                }
                = done all
                = rnd + rnd 1
            }

            : ~ i total 0
            : ~ i got 0
            : ~ i j 0
            ~ < j nchunks {
                ?? ( job_await # *JobNode . sw job ?? ( vec_get [i] tids j ) { T x → x F → 0 } ) {
                    T r → { = total + total ( result_decode r ) = got + got 1 ( vec_free [u] r ) }
                    F → {}
                }
                = j + j 1
            }

            ( nurl_print `result = ` ) ( nurl_print_int total )
            ( nurl_print `  (` ) ( nurl_print_int got ) ( nurl_print `/` ) ( nurl_print_int nchunks )
            ( nurl_print ` chunks returned)\n` )
            ? ! done { ( nurl_print `swarm: warning — some chunks did not return in time\n` ) } {}

            ( vec_free [i] tids )
            ( shard_free chunks )
            ( swarm_free sw )
            ( relay_close rc )
            ^ ? done 0 1
        }
        F e → { ( nurl_print `swarm: submit could not dial relay\n` ) ^ 1 }
    }
}

// ── CLI ───────────────────────────────────────────────────────────

@ usage → v {
    ( nurl_print `swarm — distributed compute cluster\n\n` )
    ( nurl_print `  swarm relay  <host> <port> [--v|--verbose]\n` )
    ( nurl_print `  swarm worker <host> <port> [id] [rounds]\n` )
    ( nurl_print `  swarm submit <host> <port> <primes|sumsq> <lo> <hi>\n\n` )
    ( nurl_print `A worker joins the cluster just by running; submit shards a real\n` )
    ( nurl_print `numeric range across the live workers and sums the partial results.\n` )
    ( nurl_print `--v / --verbose makes the relay log each peer connect/disconnect.\n` )
}

@ arg_int i idx → i {
    : String s ( env_arg idx )
    : i v ( nurl_str_to_int ( string_data s ) )
    ( string_free s )
    ^ v
}

@ arg_eq i idx s lit → b {
    : String s ( env_arg idx )
    : b eq ? != 0 ( nurl_str_eq ( string_data s ) lit ) T F
    ( string_free s )
    ^ eq
}

// True if arg `idx` is the verbose flag in either spelling.
@ arg_is_verbose i idx → b {
    : String s ( env_arg idx )
    : b f ? != 0 ( nurl_str_eq ( string_data s ) `--v` ) T ? != 0 ( nurl_str_eq ( string_data s ) `--verbose` ) T F
    ( string_free s )
    ^ f
}

@ main → i {
    : i argc ( env_args_count )
    ? < argc 2 { ( usage ) ^ 1 } {}

    : ~ i rc 0
    ? ( arg_eq 1 `relay` ) {
        // Scan args after the subcommand: the verbose flag may appear anywhere;
        // host and port are the first two non-flag positionals.
        : ~ i vflag 0
        : ~ String host ( string_new )
        : ~ i port 0
        : ~ i seen 0
        : ~ i ai 2
        ~ < ai argc {
            ? ( arg_is_verbose ai ) { = vflag 1 } {
                ? == seen 0 { ( string_free host ) = host ( env_arg ai ) = seen 1 } {
                    ? == seen 1 { = port ( arg_int ai ) = seen 2 } {}
                }
            }
            = ai + ai 1
        }
        ? < seen 2 { ( nurl_print `usage: swarm relay <host> <port> [--v|--verbose]\n` ) = rc 1 } {
            = rc ( run_relay ( string_data host ) port vflag )
        }
        ( string_free host )
    } {
        ? ( arg_eq 1 `worker` ) {
            ? < argc 4 { ( nurl_print `usage: swarm worker <host> <port> [id] [rounds]\n` ) = rc 1 } {
                : String host ( env_arg 2 )
                : i id ? > argc 4 ( arg_int 4 ) ( rand_u64 )
                : i rounds ? > argc 5 ( arg_int 5 ) 0
                = rc ( run_worker ( string_data host ) ( arg_int 3 ) id rounds )
                ( string_free host )
            }
        } {
            ? ( arg_eq 1 `submit` ) {
                ? < argc 6 { ( nurl_print `usage: swarm submit <host> <port> <primes|sumsq> <lo> <hi>\n` ) = rc 1 } {
                    : String host ( env_arg 2 )
                    : i kind ? ( arg_eq 4 `sumsq` ) ( kind_sumsq ) ( kind_primes )
                    = rc ( run_submit ( string_data host ) ( arg_int 3 ) kind ( arg_int 5 ) ( arg_int 6 ) )
                    ( string_free host )
                }
            } {
                ( usage ) = rc 1
            }
        }
    }
    ^ rc
}
