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
$ `stdlib/core/rcbox.nu`
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

: SwarmImpl {
    Transport transport
    Ring ring
    Roster roster
    JobNode job
    ( Vec u ) self_pk
    i self_id
    i role
    ( Vec u ) group
}

// A Swarm is a handle on the node bundle in an rcbox (stdlib/core/rcbox.nu):
// every copy is the same node, and the last owner releases it — the
// transport, ring, roster and job node with it.
: Swarm { s ctl }

@ Swarm_share Swarm h → Swarm { ^ @ Swarm { # s ( rcbox_share # i . h ctl ) } }

@ Swarm_drop sink Swarm h → v {
    ( mem_forget h )
    ( rcbox_release [SwarmImpl] # i . h ctl )
}

@ __Swarm_ptr Swarm h → *SwarmImpl { ^ ( rcbox_ptr [SwarmImpl] # i . h ctl ) }

@ swarm_new RelayClient rc i id i role → Swarm {
    : ( Vec u ) me ( pk_from_id id )
    : Transport tr ( transport_open # s 0 rc 1 )
    : Ring ring ( ring_new )
    : Roster roster ( roster_new )
    : JobNode jn ( job_node_new tr ring me id )
    // A worker is itself a ring member; the coordinator (client) never is.
    ? == role ( role_worker ) { ( roster_add roster ring me id ( swarm_vnodes ) ) } {}
    ^ @ Swarm { # s ( rcbox_new [SwarmImpl] @ SwarmImpl { tr ring roster jn me id role ( swarm_group_id ) } ) }
}

// Let go of `sw` now rather than at the end of its owner's scope (optional).
@ swarm_free sink Swarm sw → v {}

// How many workers this node has folded into its ring.
@ swarm_worker_count Swarm sw__h → i {
    : *SwarmImpl sw ( __Swarm_ptr sw__h )
    ^ ( roster_count . sw roster )
}

@ swarm_join_group Swarm sw__h → v {
    : *SwarmImpl sw ( __Swarm_ptr sw__h )
    ?? ( transport_group_join . sw transport . sw group ) { T _ → {} F _ → {} }
}

// Announce ourselves to the group. `want` asks hearers to reply so a newcomer
// learns the existing members.
@ swarm_announce Swarm sw__h i want → v {
    : *SwarmImpl sw ( __Swarm_ptr sw__h )
    : ( Vec u ) msg ( hello_build . sw self_id . sw role want . sw self_pk )
    ?? ( transport_broadcast . sw transport . sw group msg ) { T _ → {} F _ → {} }
}

@ swarm_on_hello Swarm sw__h Hello h → v {
    : *SwarmImpl sw ( __Swarm_ptr sw__h )
    // Only workers join the ring; a client announcing itself is reachable but
    // owns no keys.
    ? == . h role ( role_worker ) {
        ( roster_add . sw roster . sw ring . h pubkey . h id ( swarm_vnodes ) )
        ( transport_add_peer . sw transport . h pubkey )
    } {}
    // Reply to a discovery request unless it is our own broadcast echoed back.
    ? & == . h want 1 ! ( bytes_eq . h pubkey . sw self_pk ) {
        : ( Vec u ) reply ( hello_build . sw self_id . sw role 0 . sw self_pk )
        ?? ( transport_send . sw transport . h pubkey reply ) { T _ → {} F _ → {} }
    } {}
}

// Drain inbound transport messages, dispatching census HELLO and job traffic.
@ swarm_pump Swarm sw__h i max → v {
    : *SwarmImpl sw ( __Swarm_ptr sw__h )
    : ~ b more T
    ~ more {
        ?? ( transport_recv . sw transport max ) {
            T tm → {
                : i b0 ?? ( vec_get [u] . tm payload 0 ) { T x → # i x F → 255 }
                ? == b0 ( census_hello_t ) {
                    : Hello h ( hello_decode . tm payload )
                    ( swarm_on_hello sw__h h )
                } {
                    : JobMsg m ( jobmsg_decode . tm payload )
                    ? == . m mtype ( job_submit_t ) { ( job_on_submit . sw job m ) } {}
                    ? == . m mtype ( job_result_t ) { ( job_on_result . sw job m ) } {}
                }
            }
            F → { = more F }
        }
    }
}

// ── roles ─────────────────────────────────────────────────────────

@ run_relay s host i port i vflag → i {
    ?? ( relay_server_start host port ) {
        T rs → {
            ( relay_server_set_verbose rs vflag )
            ( nurl_print `swarm relay listening on ` ) ( nurl_print host )
            ( nurl_print `:` ) ( nurl_println_int port )
            ? == vflag 1 { ( nurl_print ` (verbose: logging peer connect/disconnect)` ) } {}
            ( nurl_print `\n` )
            ( relay_server_run rs )
            ^ 0
        }
        F e → { ( nurl_print `swarm: relay failed to bind\n` ) ^ 1 }
    }
}

@ swarm_register_handlers Swarm sw__h → v {
    : *SwarmImpl sw ( __Swarm_ptr sw__h )
    ( job_register . sw job ( kind_primes ) ( primes_handler ) )
    ( job_register . sw job ( kind_sumsq ) ( sumsq_handler ) )
}

@ run_worker s host i port i id i rounds → i {
    ?? ( relay_dial host port ) {
        T rc → {
            : ( Vec u ) reg ( pk_from_id id )
            ?? ( relay_register rc reg ) { T _ → {} F _ → {} }
            ( relay_set_timeout rc 250 )
            : Swarm sw ( swarm_new rc id ( role_worker ) )
            ( swarm_register_handlers sw )
            ( swarm_join_group sw )
            ( swarm_announce sw 1 )  // "I'm here — existing members, identify yourselves"
            ( nurl_print `swarm worker ` ) ( nurl_print_int id ) ( nurl_print ` ready (` )
            ( nurl_print_int ( swarm_worker_count sw ) ) ( nurl_print ` known)\n` )
            // Daemon loop. rounds<=0 means run until killed.
            : ~ i t 0
            ~ | <= rounds 0 < t rounds { ( swarm_pump sw 200 ) = t + t 1 }
            ( relay_close rc )
            ^ 0
        }
        F e → { ( nurl_print `swarm: worker could not dial relay\n` ) ^ 1 }
    }
}

// Discover the live workers: announce, then pump a short window collecting the
// HELLO replies that fold workers into the ring.
@ swarm_discover Swarm sw i rounds → v {
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
            ( relay_set_timeout rc 250 )
            : Swarm sw ( swarm_new rc myid ( role_client ) )
            : *SwarmImpl swp ( __Swarm_ptr sw )
            ( swarm_join_group sw )
            ( swarm_discover sw 8 )

            : i nworkers ( swarm_worker_count sw )
            ? == nworkers 0 {
                ( nurl_print `swarm: no workers found — start some with 'swarm worker'\n` )
                ( relay_close rc )
                ^ 1
            } {}

            : i nchunks ? > * nworkers 4 256 256 * nworkers 4
            ( nurl_print `swarm: ` ) ( nurl_print_int nworkers ) ( nurl_print ` worker(s), ` )
            ( nurl_print_int nchunks ) ( nurl_print ` chunk(s)\n` )

            : ( Vec Chunk ) chunks ( shard lo hi nchunks )
            : ( Vec i ) tids ( vec_new [i] )
            : ~ i i 0
            ~ < i nchunks {
                : Chunk c ?? ( vec_get [Chunk] chunks i ) { T x → x F → @ Chunk { 0 0 } }
                : ( Vec u ) key ( chunk_key i )
                : ( Vec u ) payload ( chunk_payload . c lo . c hi )
                ( vec_push [i] tids ( job_submit . swp job kind key payload ) )
                = i + i 1
            }

            // Collect until every task has landed or we give up.
            : ~ i rnd 0
            : ~ b done F
            ~ & ! done < rnd 400 {
                ( swarm_pump sw 200 )
                : ~ b all T : ~ i j 0
                ~ < j nchunks {
                    ? ! ( job_has . swp job ?? ( vec_get [i] tids j ) { T x → x F → 0 } ) { = all F } {}
                    = j + j 1
                }
                = done all
                = rnd + rnd 1
            }

            : ~ i total 0
            : ~ i got 0
            : ~ i j 0
            ~ < j nchunks {
                ?? ( job_await . swp job ?? ( vec_get [i] tids j ) { T x → x F → 0 } ) {
                    T r → { = total + total ( result_decode r ) = got + got 1 }
                    F → {}
                }
                = j + j 1
            }

            ( nurl_print `result = ` ) ( nurl_print_int total )
            ( nurl_print `  (` ) ( nurl_print_int got ) ( nurl_print `/` ) ( nurl_print_int nchunks )
            ( nurl_print ` chunks returned)\n` )
            ? ! done { ( nurl_print `swarm: warning — some chunks did not return in time\n` ) } {}

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
    ^ v
}

@ arg_eq i idx s lit → b {
    : String s ( env_arg idx )
    : b eq ? != 0 ( nurl_str_eq ( string_data s ) lit ) T F
    ^ eq
}

// True if arg `idx` is the verbose flag in either spelling.
@ arg_is_verbose i idx → b {
    : String s ( env_arg idx )
    : b f ? != 0 ( nurl_str_eq ( string_data s ) `--v` ) T ? != 0 ( nurl_str_eq ( string_data s ) `--verbose` ) T F
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
                ? == seen 0 { = host ( env_arg ai ) = seen 1 } {
                    ? == seen 1 { = port ( arg_int ai ) = seen 2 } {}
                }
            }
            = ai + ai 1
        }
        ? < seen 2 { ( nurl_print `usage: swarm relay <host> <port> [--v|--verbose]\n` ) = rc 1 } {
            = rc ( run_relay ( string_data host ) port vflag )
        }
    } {
        ? ( arg_eq 1 `worker` ) {
            ? < argc 4 { ( nurl_print `usage: swarm worker <host> <port> [id] [rounds]\n` ) = rc 1 } {
                : String host ( env_arg 2 )
                : i id ? > argc 4 ( arg_int 4 ) ( rand_u64 )
                : i rounds ? > argc 5 ( arg_int 5 ) 0
                = rc ( run_worker ( string_data host ) ( arg_int 3 ) id rounds )
            }
        } {
            ? ( arg_eq 1 `submit` ) {
                ? < argc 6 { ( nurl_print `usage: swarm submit <host> <port> <primes|sumsq> <lo> <hi>\n` ) = rc 1 } {
                    : String host ( env_arg 2 )
                    : i kind ? ( arg_eq 4 `sumsq` ) ( kind_sumsq ) ( kind_primes )
                    = rc ( run_submit ( string_data host ) ( arg_int 3 ) kind ( arg_int 5 ) ( arg_int 6 ) )
                }
            } {
                ( usage ) = rc 1
            }
        }
    }
    ^ rc
}
