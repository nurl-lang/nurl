// example/mqtt_listener.nu — MQTT v5 background listener thread.
//
// A subscriber connection is handed to mqtt_listen, which spawns a
// reader thread that owns the socket and feeds inbound messages through
// a channel. The main thread meanwhile opens a second (publisher)
// connection, sends three messages, and pulls them back out of the
// listener channel — proving inbound delivery runs concurrently with
// the application's own work.
//
//   broker : emqx.homecloud.fi:8883  (TLS)
//   topic  : nurl/listener/qwerty
//
// Build & run:
//   ./nurl.sh example/mqtt_listener.nu example/mqtt_listener
//   ./example/mqtt_listener

$ `stdlib/ext/mqtt.nu`

@ main → i {
    : s topic `nurl/listener/qwerty`

    ( nurl_print `MQTT v5 background listener → emqx.homecloud.fi:8883 (TLS)\n` )

    // ── subscriber: connect, subscribe, hand to a reader thread ──
    : !MqttClient MqttErr so ( mqtt_connect
        `emqx.homecloud.fi` 8883 `qwerty-sub` `qwerty` `qwerty` )
    ?? so {
        T sub → {
            : !v MqttErr sr ( mqtt_subscribe sub topic )
            ?? sr {
                T → { ( nurl_print `subscriber connected + subscribed.\n` ) }
                F se → {
                    ( nurl_eprint `subscribe failed: ` )
                    ( nurl_eprint ( mqtt_err_name se ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect sub ) ^ 1
                }
            }

            : !MqttListener MqttErr lo ( mqtt_listen sub )
            ?? lo {
                T lst → {
                    ( nurl_print `background listener thread started.\n` )

                    // ── publisher: a separate connection ──
                    : !MqttClient MqttErr po ( mqtt_connect
                        `emqx.homecloud.fi` 8883 `qwerty-pub` `qwerty` `qwerty` )
                    ?? po {
                        T pc → {
                            ( nurl_print `publisher connected; sending 3 messages...\n` )
                            : ~ i n 0
                            ~ < n 3 {
                                : String body ( string_with_cap 16 )
                                ( string_push_str body `msg-` )
                                ( string_push_int body n )
                                : !v MqttErr pr ( mqtt_publish1 pc topic ( string_data body ) )
                                ( string_free body )
                                ?? pr { T → {} F _ → {} }
                                = n + n 1
                            }

                            // pull the 3 messages out of the listener channel
                            : ~ i got 0
                            : ~ b ok T
                            ~ < got 3 {
                                ?? ( mqtt_listener_recv lst ) {
                                    T m → {
                                        ( nurl_print `  received [` )
                                        ( nurl_print ( string_data . m topic ) )
                                        ( nurl_print `] ` )
                                        ( nurl_print ( string_data . m payload ) )
                                        ( nurl_print `\n` )
                                        ( mqtt_message_free m )
                                    }
                                    F _ → { = ok F = got 2 }
                                }
                                = got + got 1
                            }

                            ( mqtt_disconnect pc )
                            ( mqtt_listener_stop lst )
                            ? ok {
                                ( nurl_print `ALL OK — listener delivered all 3 messages.\n` )
                                ^ 0
                            } {
                                ( nurl_print `listener channel closed early.\n` )
                                ^ 1
                            }
                        }
                        F pe → {
                            ( nurl_eprint `publisher connect failed: ` )
                            ( nurl_eprint ( mqtt_err_name pe ) ) ( nurl_eprint `\n` )
                            ( mqtt_listener_stop lst )
                            ^ 1
                        }
                    }
                }
                F le → {
                    ( nurl_eprint `mqtt_listen failed: ` )
                    ( nurl_eprint ( mqtt_err_name le ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect sub ) ^ 1
                }
            }
        }
        F e → {
            ( nurl_eprint `subscriber connect failed: ` )
            ( nurl_eprint ( mqtt_err_name e ) ) ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
