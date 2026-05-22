// example/mqtt_properties.nu — MQTT v5 user properties.
//
// Publishes a message carrying two MQTT 5 user properties (key/value
// string pairs) and confirms the broker forwards them unaltered to the
// subscriber.
//
//   broker : emqx.homecloud.fi:8883  (TLS)
//   topic  : nurl/props/qwerty
//
// Build & run:
//   ./nurl.sh example/mqtt_properties.nu example/mqtt_properties
//   ./example/mqtt_properties

$ `stdlib/ext/mqtt.nu`

@ main → i {
    : s topic `nurl/props/qwerty`

    ( nurl_print `MQTT v5 user properties → emqx.homecloud.fi:8883 (TLS)\n` )

    : !MqttClient NetErr o ( mqtt_connect
        `emqx.homecloud.fi` 8883 `qwerty` `qwerty` `qwerty` )
    ?? o {
        T cl → {
            ( nurl_print `connected.\n` )

            : !v NetErr sr ( mqtt_subscribe cl topic )
            ?? sr {
                T → { ( nurl_print `subscribed to ` ) ( nurl_print topic ) ( nurl_print `\n` ) }
                F se → {
                    ( nurl_eprint `subscribe failed: ` )
                    ( nurl_eprint ( net_err_name se ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            // build two user properties as a Vec ( Pair String String )
            : ( Vec ( Pair String String ) ) props ( vec_new [( Pair String String )] )
            ( vec_push [( Pair String String )] props
              @ ( Pair String String ) { ( string_from `content-type` ) ( string_from `text/plain` ) } )
            ( vec_push [( Pair String String )] props
              @ ( Pair String String ) { ( string_from `sender` ) ( string_from `nurl-mqtt` ) } )

            : !v NetErr pr ( mqtt_publish_props cl topic `payload with props` 0 props )
            ( mqtt_props_free props )
            ?? pr {
                T → { ( nurl_print `published with 2 user properties.\n` ) }
                F pe → {
                    ( nurl_eprint `publish failed: ` )
                    ( nurl_eprint ( net_err_name pe ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            : !MqttMessage NetErr rr ( mqtt_receive cl )
            ?? rr {
                T m → {
                    : i np ( vec_len [( Pair String String )] . m props )
                    ( nurl_print `received with ` )
                    ( nurl_print ( nurl_str_int np ) )
                    ( nurl_print ` user properties:\n` )
                    : s ct ( mqtt_message_prop m `content-type` )
                    : s sn ( mqtt_message_prop m `sender` )
                    ( nurl_print `  content-type = ` ) ( nurl_print ct ) ( nurl_print `\n` )
                    ( nurl_print `  sender       = ` ) ( nurl_print sn ) ( nurl_print `\n` )
                    : i ok1 ( nurl_str_eq ct `text/plain` )
                    : i ok2 ( nurl_str_eq sn `nurl-mqtt` )
                    ( mqtt_message_free m )
                    ( mqtt_disconnect cl )
                    ? & != 0 ok1 != 0 ok2 {
                        ( nurl_print `USER PROPERTIES round-trip OK.\n` )
                        ^ 0
                    } {
                        ( nurl_print `property mismatch.\n` )
                        ^ 1
                    }
                }
                F re → {
                    ( nurl_eprint `receive failed: ` )
                    ( nurl_eprint ( net_err_name re ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
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
