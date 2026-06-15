// examples/replicated_counter.nu — a PNCounter replicated across the group by
// CRDT gossip over the overlay (TODO §7.4 Phase 6). Each node increments its
// OWN replica slot, periodically broadcasts its encoded counter to the group
// (transport_broadcast → relay multicast), and merges every counter it
// receives. Because PNCounter.merge is a CRDT merge, all nodes converge to
// the same total with no coordination.
//
//   ./nurl.sh examples/replicated_counter.nu <relay_host> <relay_port> <replica_id>
//
// Run a relay (examples/relay.nu) and several of these with distinct ids; the
// printed value converges to the sum of everyone's increments.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/net/transport.nu`
$ `stdlib/dist/crdt.nu`
$ `stdlib/dist/replicator.nu`
$ `stdlib/dist/identity.nu`

@ pk_for i id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + id k ) = k + k 1 } ^ v }
@ group_id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + 200 k ) = k + k 1 } ^ v }

@ main → i {
    : i argc ( env_args_count )
    : String host ? > argc 1 ( env_arg 1 ) ( string_from `127.0.0.1` )
    : i port ? > argc 2 {
        : String ps ( env_arg 2 ) : i p ( nurl_str_to_int ( string_data ps ) ) ( string_free ps ) p
    } 47700
    : i rid ? > argc 3 {
        : String rs ( env_arg 3 ) : i r ( nurl_str_to_int ( string_data rs ) ) ( string_free rs ) r
    } 0

    ?? ( relay_dial ( string_data host ) port ) {
        T rc → {
            : ( Vec u ) self_pk ( pk_for + 1 rid )
            // The CRDT replica id comes from the PUBKEY, not the CLI arg: every
            // node derives the same id for a given pubkey with no coordination,
            // so distinct replicas never collide into one counter slot.
            : i crep ( identity_stable_id self_pk )
            ?? ( relay_register rc self_pk ) { T _ → {} F _ → {} }
            ( relay_set_timeout rc 300 )
            : *Transport tr # *Transport ( transport_open # s 0 rc 1 )
            : ( Vec u ) g ( group_id )
            ?? ( transport_group_join tr g ) { T _ → {} F _ → {} }

            : *PNCounter ctr ( pncounter_new )

            : ~ i round 0
            ~ < round 5 {
                ( pncounter_inc ctr crep 1 )           // count our own work (pubkey-stable slot)
                : ( Vec u ) wire ( pncounter_encode ctr )
                ?? ( transport_broadcast tr g wire ) { T _ → {} F _ → {} }
                ( vec_free [u] wire )
                // drain inbound counters and merge them
                : ~ b more T
                ~ more {
                    ?? ( transport_recv tr 100 ) {
                        T m → { ( pncounter_merge_bytes ctr . m payload ) ( transport_msg_free m ) }
                        F → { = more F }
                    }
                }
                ( sleep_ms 200 )
                = round + round 1
            }

            ( nurl_print `replica ` ) ( nurl_print_int rid )
            ( nurl_print ` converged value = ` ) ( nurl_print_int ( pncounter_value ctr ) ) ( nurl_print `\n` )

            ( pncounter_free ctr )
            ( vec_free [u] self_pk ) ( vec_free [u] g )
            ( transport_free tr ) ( relay_close rc )
        }
        F e → ( nurl_print `could not reach relay\n` )
    }
    ( string_free host )
    ^ 0
}
