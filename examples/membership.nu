// examples/membership.nu — a SWIM membership node over the pubkey overlay
// (TODO §7.4 Phase 5): net/failuredetector drives net/membership, and every
// probe/ack/gossip rides net/transport addressed by PUBLIC KEY (direct via
// securedgram when possible, relayed otherwise). This is the adapter that
// turns the pure FD step machine into a live detector.
//
//   ./nurl.sh examples/membership.nu <relay_host> <relay_port>
//
// (Illustrative wiring — run a relay with examples/relay.nu and several of
// these; each learns the others via net/rendezvous in a full deployment.)

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/async.nu`
$ `stdlib/std/time.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/net/transport.nu`
$ `stdlib/net/membership.nu`
$ `stdlib/net/failuredetector.nu`

@ my_pk → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + 1 k ) = k + k 1 } ^ v }

// Send a membership message (PING/ACK/PING-REQ + gossip) to a peer pubkey
// over the transport — direct or relayed, the FD neither knows nor cares.
@ send_msg * Transport tr ( Vec u ) dst i mtype i seq * PkMemberTable tbl → v {
    : ( Vec s ) g ( pktable_gossip tbl 6 )
    : PkMsg m @ PkMsg { mtype seq ( vec_new [u] ) g }
    : ( Vec u ) wire ( pkmsg_encode m )
    ?? ( transport_send tr dst wire ) { T _ → {} F _ → {} }
    ( pkmsg_free m ) ( vec_free [u] wire )
}

// Perform one FD action on the wire.
@ do_action * Transport tr FdAction a * PkMemberTable tbl → v {
    ? == . a kind ( fd_do_ping ) { ( send_msg tr . a target ( pk_ping ) . a seq tbl ) } {}
    ? == . a kind ( fd_do_preq ) {
        // ask each relay to probe the target on our behalf
        : i n ( vec_len [s] . a relays )
        : ~ i k 0
        ~ < k n {
            : s pp ?? ( vec_get [s] . a relays k ) { T x → x F → # s 0 }
            ? != # i pp 0 { : *PkMember rm # *PkMember pp ( send_msg tr . rm pubkey ( pk_pingreq ) . a seq tbl ) } {}
            = k + k 1
        }
    } {}
}

// Drain inbound messages, feeding acks/gossip to the FD and answering pings.
@ pump * Transport tr * FdState fd * PkMemberTable tbl ( Vec u ) self_pk i now → v {
    : ~ b more T
    ~ more {
        ?? ( transport_recv tr 50 ) {
            T msg → {
                : PkMsg m ( pkmsg_decode . msg payload )
                ( fd_on_gossip fd m now )
                ? == . m mtype ( pk_ack ) { ( fd_on_ack fd . m seq now ) } {}
                ? == . m mtype ( pk_ping ) { ( send_msg tr . msg src ( pk_ack ) . m seq tbl ) } {}
                ( pkmsg_free m )
                ( transport_msg_free msg )
            }
            F → { = more F }
        }
    }
}

@ main → i {
    : i argc ( env_args_count )
    : String host ? > argc 1 ( env_arg 1 ) ( string_from `127.0.0.1` )
    : i port ? > argc 2 {
        : String ps ( env_arg 2 ) : i p ( nurl_str_to_int ( string_data ps ) ) ( string_free ps ) p
    } 47700

    ?? ( relay_dial ( string_data host ) port ) {
        T rc → {
            : ( Vec u ) self_pk ( my_pk )
            ?? ( relay_register rc self_pk ) { T _ → {} F _ → {} }
            ( relay_set_timeout rc 200 )
            : *Transport tr # *Transport ( transport_open # s 0 rc 1 )
            : *PkMemberTable tbl ( pktable_new self_pk 2000000000 8000000000 3 8 )
            // ( transport_add_peer + pktable_apply for each known peer … )
            : *FdState fd ( fd_new # s tbl 1000000000 300000000 2000000000 3 )

            : ~ i ticks 0
            ~ < ticks 3 {
                : i now ( monotonic_ns )
                : FdAction a ( fd_tick fd now )
                ( do_action tr a tbl )
                ( fd_action_free a )
                ( pump tr fd tbl self_pk now )
                : ( Vec s ) dead ( fd_sweep fd now )
                ( _pk_dead_free dead )
                ( sleep_ms 200 )
                = ticks + ticks 1
            }
            ( nurl_print `membership node ran (members: ` ) ( nurl_print_int ( pktable_count tbl ) ) ( nurl_print `)\n` )

            ( fd_free fd ) ( pktable_free tbl ) ( transport_free tr )
            ( vec_free [u] self_pk ) ( relay_close rc )
        }
        F e → ( nurl_print `could not reach relay\n` )
    }
    ( string_free host )
    ^ 0
}
