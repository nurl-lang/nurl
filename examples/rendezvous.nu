// examples/rendezvous.nu — a deployable rendezvous (signaling) server for
// TODO §7.4 Phase 3. Peers REGISTER their pubkey → candidate endpoints +
// chosen relay; any peer LOOKs another up by pubkey to learn where to try a
// direct path (and the relay fallback). NO application data flows here.
//
//   ./nurl.sh examples/rendezvous.nu [host] [port]      # default 0.0.0.0:47703
//
// A peer uses the client API (stdlib/net/rendezvous.nu):
//
//     ?? ( rz_client_connect rz_host rz_port ) { T rc → {
//         : s rp ( peer_record_new my_pubkey my_relay_host my_relay_port )
//         : *PeerRecord r # *PeerRecord rp
//         ( peer_record_add_endpoint r host_cand_ip host_cand_port )   // from net/nat
//         ( peer_record_add_endpoint r srflx_ip srflx_port )
//         ( rz_register_self rc r )                       // publish
//         : s peer ( rz_lookup_peer rc other_pubkey )     // discover a peer
//         // → feed peer's endpoints to transport_try_direct, relay as fallback
//     } F e → {} }

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/rendezvous.nu`

@ main → i {
    : i argc ( env_args_count )
    : String host ? > argc 1 ( env_arg 1 ) ( string_from `0.0.0.0` )
    : i port ? > argc 2 {
        : String ps ( env_arg 2 ) : i p ( nurl_str_to_int ( string_data ps ) ) ( string_free ps ) p
    } 47703

    ?? ( rz_server_start ( string_data host ) port ) {
        T rs → {
            : *RzServer p # *RzServer ( nurl_alloc Z RzServer )
            = . p lst . rs lst
            = . p records . rs records
            ( nurl_print `rendezvous listening on ` ) ( nurl_print ( string_data host ) )
            ( nurl_print `:` ) ( nurl_print_int port )
            ( rz_server_run p )
            ( rz_server_free p )
        }
        F e → ( nurl_print `rendezvous failed to bind\n` )
    }
    ( string_free host )
    ^ 0
}
