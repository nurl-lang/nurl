// examples/relay.nu — a deployable DERP-style relay daemon (TODO §7.4
// Phase 2). NAT'd peers that can't open a direct path dial out to a relay,
// register their public key, and exchange opaque (already E2E-encrypted)
// datagrams addressed by the *destination's* pubkey. The relay never
// decrypts — it just forwards by pubkey.
//
//   ./nurl.sh examples/relay.nu [host] [port]      # default 0.0.0.0:47700
//
// A peer uses the client API (stdlib/net/relay.nu):
//
//     : !RelayClient NetErr d ( relay_dial relay_host relay_port )
//     ?? d { T rc → {
//         ( relay_register rc my_pubkey )            // announce identity
//         ( relay_send rc dest_pubkey opaque_bytes ) // forward to a peer
//         ?? ( relay_recv rc ) {                     // {src_pubkey, payload}
//             T m → { /* . m src, . m payload */ ( relay_msg_free m ) }
//             F → {} }
//         ( relay_close rc )
//     } F e → {} }

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/relay.nu`

@ main → i {
    : i argc ( env_args_count )
    : String host ? > argc 1 ( env_arg 1 ) ( string_from `0.0.0.0` )
    : i port ? > argc 2 {
        : String ps ( env_arg 2 ) : i p ( nurl_str_to_int ( string_data ps ) ) ( string_free ps ) p
    } 47700

    ?? ( relay_server_start ( string_data host ) port ) {
        T rs → {
            : *RelayServer p # *RelayServer ( nurl_alloc Z RelayServer )
            = . p lst . rs lst
            = . p clients . rs clients
            = . p groups . rs groups
            ( nurl_print `relay listening on ` ) ( nurl_print ( string_data host ) )
            ( nurl_print `:` ) ( nurl_print_int port )
            ( relay_server_run p )   // blocks until the listener is closed
            ( relay_server_free p )
        }
        F e → ( nurl_print `relay failed to bind\n` )
    }
    ( string_free host )
    ^ 0
}
