// example/mqtt_features.nu — MQTT v5 hardening features.
//
// Connects with a Last Will & Testament and a session-expiry interval,
// publishes a RETAINED message, subscribes at QoS 1, and confirms the
// broker hands back the retained message on subscribe.
//
//   broker : emqx.homecloud.fi:8883  (TLS)
//
// Build & run:
//   ./nurl.sh example/mqtt_features.nu example/mqtt_features
//   ./example/mqtt_features

$ `stdlib/ext/mqtt.nu`

@ main → i {
    : s rtopic `nurl/retain/qwerty`

    ( nurl_print `MQTT v5 features → emqx.homecloud.fi:8883 (TLS)\n` )

    // CONNECT with a will message (topic, payload, QoS 1) and a
    // 300-second session-expiry interval.
    : MqttConfig cfg @ MqttConfig {
        `qwerty` `qwerty` `qwerty` 60 T
        `nurl/status/qwerty` `client gone` 1 300 }

    : !MqttClient MqttErr o ( mqtt_connect_cfg `emqx.homecloud.fi` 8883 cfg )
    ?? o {
        T cl → {
            ( nurl_print `connected — will + session-expiry accepted.\n` )

            // publish a RETAINED message
            : !v MqttErr pr ( mqtt_publish_retain cl rtopic `retained value` 0 )
            ?? pr {
                T → {
                    ( nurl_print `published retained → ` )
                    ( nurl_print rtopic ) ( nurl_print `\n` )
                }
                F pe → {
                    ( nurl_eprint `retain publish failed: ` )
                    ( nurl_eprint ( mqtt_err_name pe ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            // subscribe at QoS 1 — the broker delivers the retained
            // message immediately after the SUBACK.
            : !v MqttErr sr ( mqtt_subscribe_qos cl rtopic 1 )
            ?? sr {
                T → {
                    ( nurl_print `subscribed (max QoS 1) to ` )
                    ( nurl_print rtopic ) ( nurl_print `\n` )
                }
                F se → {
                    ( nurl_eprint `subscribe failed: ` )
                    ( nurl_eprint ( mqtt_err_name se ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            : !MqttMessage MqttErr rr ( mqtt_receive cl )
            ?? rr {
                T m → {
                    ( nurl_print `retained message received: ` )
                    ( nurl_print ( string_data . m payload ) ) ( nurl_print `\n` )
                    : i ok ( nurl_str_eq ( string_data . m payload ) `retained value` )
                    ( mqtt_message_free m )
                    ? != 0 ok {
                        ( nurl_print `retain delivery OK.\n` )
                    } {
                        ( nurl_print `retained payload mismatch.\n` )
                        ( mqtt_disconnect cl ) ^ 1
                    }
                }
                F re → {
                    ( nurl_eprint `receive failed: ` )
                    ( nurl_eprint ( mqtt_err_name re ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            // an empty retained payload deletes the retained message —
            // leave the broker clean.
            : !v MqttErr clr ( mqtt_publish_retain cl rtopic `` 0 )
            ?? clr {
                T → { ( nurl_print `retained message cleared.\n` ) }
                F _ → {}
            }

            ( mqtt_disconnect cl )
            ( nurl_print `ALL OK — will · session-expiry · retain · subscribe-QoS.\n` )
            ^ 0
        }
        F e → {
            ( nurl_eprint `connect failed: ` )
            ( nurl_eprint ( mqtt_err_name e ) ) ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
