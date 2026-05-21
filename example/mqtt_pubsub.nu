// example/mqtt_pubsub.nu — MQTT v5 publish + subscribe round-trip.
//
// Connects to the broker, SUBSCRIBEs to a topic, PUBLISHes a message
// to that same topic, then reads the message the broker echoes back
// to us as a subscriber — proving publish and subscribe both work.
//
//   broker   : emqx.homecloud.fi:8883  (TLS)
//   topic    : nurl/pubsub/qwerty
//   protocol : MQTT 5.0
//
// Build & run:
//   ./nurl.sh example/mqtt_pubsub.nu example/mqtt_pubsub
//   ./example/mqtt_pubsub

$ `stdlib/ext/mqtt.nu`

@ main → i {
    : s topic `nurl/pubsub/qwerty`
    : s msg   `hello from NURL mqtt`

    ( nurl_print `MQTT v5 pub/sub → emqx.homecloud.fi:8883 (TLS)\n` )

    : !TcpConn NetErr o ( mqtt_open
        `emqx.homecloud.fi` 8883 `qwerty` `qwerty` `qwerty` )
    ?? o {
        T c → {
            ( nurl_print `connected.\n` )

            : !v NetErr sr ( mqtt_subscribe c topic )
            ?? sr {
                T → {
                    ( nurl_print `subscribed: ` ) ( nurl_print topic ) ( nurl_print `\n` )
                }
                F se → {
                    ( nurl_eprint `subscribe failed: ` )
                    ( nurl_eprint ( net_err_name se ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect c )
                    ^ 1
                }
            }

            : !v NetErr pr ( mqtt_publish c topic msg )
            ?? pr {
                T → {
                    ( nurl_print `published: ` ) ( nurl_print msg ) ( nurl_print `\n` )
                }
                F pe → {
                    ( nurl_eprint `publish failed: ` )
                    ( nurl_eprint ( net_err_name pe ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect c )
                    ^ 1
                }
            }

            : !String NetErr rr ( mqtt_read_publish c )
            ?? rr {
                T payload → {
                    ( nurl_print `received: ` )
                    ( nurl_print ( string_data payload ) )
                    ( nurl_print `\n` )
                    : i same ( nurl_str_eq ( string_data payload ) msg )
                    ( string_free payload )
                    ( mqtt_disconnect c )
                    ? != 0 same {
                        ( nurl_print `ROUND-TRIP OK — publish + subscribe verified.\n` )
                        ^ 0
                    } {
                        ( nurl_print `payload mismatch.\n` )
                        ^ 1
                    }
                }
                F re → {
                    ( nurl_eprint `receive failed: ` )
                    ( nurl_eprint ( net_err_name re ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect c )
                    ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprint `connect failed: ` )
            ( nurl_eprint ( net_err_name e ) ) ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
