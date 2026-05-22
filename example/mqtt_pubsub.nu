// example/mqtt_pubsub.nu — MQTT v5 client end-to-end exercise.
//
// connect → subscribe → publish QoS 0 → receive the echo → publish
// QoS 1 (PUBACK) → keep-alive ping → unsubscribe → disconnect, all
// against a live broker.
//
//   broker : emqx.homecloud.fi:8883  (TLS)
//   topic  : nurl/pubsub/qwerty
//
// Build & run:
//   ./nurl.sh example/mqtt_pubsub.nu example/mqtt_pubsub
//   ./example/mqtt_pubsub

$ `stdlib/ext/mqtt.nu`

@ main → i {
    : s topic `nurl/pubsub/qwerty`
    : s msg   `hello from NURL mqtt`

    ( nurl_print `MQTT v5 pub/sub → emqx.homecloud.fi:8883 (TLS)\n` )

    : !MqttClient MqttErr o ( mqtt_connect
        `emqx.homecloud.fi` 8883 `qwerty` `qwerty` `qwerty` )
    ?? o {
        T cl → {
            ( nurl_print `connected.\n` )

            : !v MqttErr sr ( mqtt_subscribe cl topic )
            ?? sr {
                T → { ( nurl_print `subscribed: ` ) ( nurl_print topic ) ( nurl_print `\n` ) }
                F se → {
                    ( nurl_eprint `subscribe failed: ` )
                    ( nurl_eprint ( mqtt_err_name se ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            : !v MqttErr pr ( mqtt_publish cl topic msg )
            ?? pr {
                T → { ( nurl_print `published (QoS 0): ` ) ( nurl_print msg ) ( nurl_print `\n` ) }
                F pe → {
                    ( nurl_eprint `publish failed: ` )
                    ( nurl_eprint ( mqtt_err_name pe ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            : !MqttMessage MqttErr rr ( mqtt_receive cl )
            ?? rr {
                T m → {
                    ( nurl_print `received [` )
                    ( nurl_print ( string_data . m topic ) )
                    ( nurl_print `]: ` )
                    ( nurl_print ( string_data . m payload ) )
                    ( nurl_print `\n` )
                    : i same ( nurl_str_eq ( string_data . m payload ) msg )
                    ( mqtt_message_free m )
                    ? != 0 same {
                        ( nurl_print `QoS 0 round-trip OK.\n` )
                    } {
                        ( nurl_print `payload mismatch.\n` )
                        ( mqtt_disconnect cl ) ^ 1
                    }
                }
                F re → {
                    ( nurl_eprint `receive failed: ` )
                    ( nurl_eprint ( mqtt_err_name re ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            : !v MqttErr q1 ( mqtt_publish1 cl `nurl/pubsub/qwerty/qos1` `qos1 payload` )
            ?? q1 {
                T → { ( nurl_print `published (QoS 1) — PUBACK received.\n` ) }
                F qe → {
                    ( nurl_eprint `QoS 1 publish failed: ` )
                    ( nurl_eprint ( mqtt_err_name qe ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            : !v MqttErr q2 ( mqtt_publish2 cl `nurl/pubsub/qwerty/qos2` `qos2 payload` )
            ?? q2 {
                T → { ( nurl_print `published (QoS 2) — PUBCOMP received.\n` ) }
                F q2e → {
                    ( nurl_eprint `QoS 2 publish failed: ` )
                    ( nurl_eprint ( mqtt_err_name q2e ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            : !v MqttErr pg ( mqtt_ping cl )
            ?? pg {
                T → { ( nurl_print `keep-alive ping → PINGRESP OK.\n` ) }
                F ge → {
                    ( nurl_eprint `ping failed: ` )
                    ( nurl_eprint ( mqtt_err_name ge ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            : !v MqttErr us ( mqtt_unsubscribe cl topic )
            ?? us {
                T → { ( nurl_print `unsubscribed.\n` ) }
                F ue → {
                    ( nurl_eprint `unsubscribe failed: ` )
                    ( nurl_eprint ( mqtt_err_name ue ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            ( mqtt_disconnect cl )
            ( nurl_print `ALL OK — connect · sub · pub QoS0/1/2 · receive · ping · unsub.\n` )
            ^ 0
        }
        F e → {
            ( nurl_eprint `connect failed: ` )
            ( nurl_eprint ( mqtt_err_name e ) ) ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
