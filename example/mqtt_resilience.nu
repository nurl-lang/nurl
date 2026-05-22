// example/mqtt_resilience.nu — MQTT v5 connection resilience.
//
// Exercises the long-lived-connection features: a deliberate
// reconnect mid-session, and the keep-alive tick loop that pings the
// broker only when the keep-alive deadline is due.
//
//   broker : emqx.homecloud.fi:8883  (TLS), keep-alive 2 s
//
// Build & run:
//   ./nurl.sh example/mqtt_resilience.nu example/mqtt_resilience
//   ./example/mqtt_resilience

$ `stdlib/ext/mqtt.nu`

@ main → i {
    : s topic `nurl/resilience/qwerty`

    // keep-alive 2 s — short enough that the tick loop below actually
    // crosses the deadline and emits a PINGREQ.
    : MqttConfig cfg @ MqttConfig {
        `qwerty` `qwerty` `qwerty` 2 T `` `` 0 0 }

    ( nurl_print `MQTT v5 resilience → emqx.homecloud.fi:8883 (TLS)\n` )

    : !MqttClient MqttErr o ( mqtt_connect_cfg `emqx.homecloud.fi` 8883 cfg )
    ?? o {
        T cl → {
            ( nurl_print `connected (keep-alive 2 s).\n` )

            : !v MqttErr p1 ( mqtt_publish1 cl topic `before reconnect` )
            ?? p1 {
                T → { ( nurl_print `published before reconnect.\n` ) }
                F e → {
                    ( nurl_eprint `publish failed: ` )
                    ( nurl_eprint ( mqtt_err_name e ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            // tear the connection down and bring it back up
            : !v MqttErr rc ( mqtt_reconnect cl `emqx.homecloud.fi` 8883 cfg )
            ?? rc {
                T → { ( nurl_print `reconnected — fresh TLS + CONNECT.\n` ) }
                F e → {
                    ( nurl_eprint `reconnect failed: ` )
                    ( nurl_eprint ( mqtt_err_name e ) ) ( nurl_eprint `\n` )
                    ^ 1
                }
            }

            : !v MqttErr p2 ( mqtt_publish1 cl topic `after reconnect` )
            ?? p2 {
                T → { ( nurl_print `published after reconnect — client still live.\n` ) }
                F e → {
                    ( nurl_eprint `post-reconnect publish failed: ` )
                    ( nurl_eprint ( mqtt_err_name e ) ) ( nurl_eprint `\n` )
                    ( mqtt_disconnect cl ) ^ 1
                }
            }

            // keep-alive: each iteration sleeps past the 2 s deadline,
            // so mqtt_keepalive_tick emits a PINGREQ and resets it.
            : ~ i k 0
            : ~ b kfail F
            ~ < k 3 {
                ( sleep_ms 2200 )
                : !v MqttErr kt ( mqtt_keepalive_tick cl )
                ?? kt {
                    T → {
                        ( nurl_print `keep-alive tick ` )
                        ( nurl_print ( nurl_str_int k ) )
                        ( nurl_print ` → ping sent.\n` )
                    }
                    F _ → { = kfail T }
                }
                = k + k 1
            }
            ? kfail {
                ( nurl_eprint `keep-alive tick failed\n` )
                ( mqtt_disconnect cl ) ^ 1
            } {}

            ( mqtt_disconnect cl )
            ( nurl_print `ALL OK — publish · reconnect · publish · keep-alive.\n` )
            ^ 0
        }
        F e → {
            ( nurl_eprint `connect failed: ` )
            ( nurl_eprint ( mqtt_err_name e ) ) ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
