// examples/transport.nu — the pubkey-addressed overlay in use (TODO §7.4
// Phase 4). A group-broadcast client: it opens a transport over a relay,
// joins a group, broadcasts one opaque payload to the whole group (the
// shape a group-audio sender uses — one uplink, the relay fans out), and
// receives messages from peers. Addressing is by public key only; the
// transport hides direct-vs-relay, NAT and roaming.
//
//   ./nurl.sh examples/transport.nu <relay_host> <relay_port>
//
// Run a relay with examples/relay.nu. The payload here is just text; a real
// app puts a distributed-compute task or an Opus audio frame there,
// E2E-encrypted with the group key.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/net/relay.nu`
$ `stdlib/net/transport.nu`

@ my_pubkey → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + 7 k ) = k + k 1 } ^ v }

@ group_id → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : ~ i k 0 ~ < k 32 { ( vec_push [u] v # u + 200 k ) = k + k 1 } ^ v }

@ frame s text i n → ( Vec u ) { : ( Vec u ) v ( vec_new [u] ) : *u sp # *u text : ~ i k 0 ~ < k n { ( vec_push [u] v # u . sp k ) = k + k 1 } ^ v }

@ main → i {
    : i argc ( env_args_count )
    : String host ? > argc 1 ( env_arg 1 ) ( string_from `127.0.0.1` )
    : i port ? > argc 2 {
        : String ps ( env_arg 2 ) : i p ( nurl_str_to_int ( string_data ps ) ) ( string_free ps ) p
    } 47700

    ?? ( relay_dial ( string_data host ) port ) {
        T rc → {
            : ( Vec u ) me ( my_pubkey )
            ?? ( relay_register rc me ) { T _ → {} F _ → {} }
            ( relay_set_timeout rc 3000 )

            // relay-only transport (no direct UDP leg in this demo)
            : *Transport t # *Transport ( transport_open # s 0 rc 1 )

            : ( Vec u ) g ( group_id )
            ?? ( transport_group_join t g ) { T _ → {} F _ → {} }

            : ( Vec u ) payload ( frame `hello-group` 11 )
            ?? ( transport_broadcast t g payload ) {
                T _ → ( nurl_print `broadcast to group sent\n` )
                F _ → ( nurl_print `broadcast failed\n` )
            }

            // receive whatever peers send back
            ?? ( transport_recv t 3000 ) {
                T m → {
                    ( nurl_print `recv ` ) ( nurl_print_int ( vec_len [u] . m payload ) ) ( nurl_print ` bytes from a peer\n` )
                    ( transport_msg_free m )
                }
                F → ( nurl_print `no message this round\n` )
            }

            ( vec_free [u] me ) ( vec_free [u] g ) ( vec_free [u] payload )
            ( transport_free t )
            ( relay_close rc )
        }
        F e → ( nurl_print `could not reach relay\n` )
    }
    ( string_free host )
    ^ 0
}
