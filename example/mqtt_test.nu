// example/mqtt_test.nu — MQTT v5 client smoke test.
//
// Connects to an MQTT broker over TLS, performs the MQTT 5.0 CONNECT
// handshake (clientId / username / password), and reports the CONNACK
// reason code.
//
//   broker   : emqx.homecloud.fi
//   port     : 8883  (MQTT over TLS)
//   clientId : qwerty
//   username : qwerty
//   password : qwerty
//   protocol : MQTT 5.0
//
// Build & run:
//   ./nurl.sh example/mqtt_test.nu example/mqtt_test
//   ./example/mqtt_test
//
// Exit 0 when the broker accepts the connection (CONNACK reason 0).

$ `stdlib/ext/mqtt.nu`

@ main → i {
    ( nurl_print `MQTT v5 → emqx.homecloud.fi:8883 (TLS), clientId=qwerty\n` )

    : !i NetErr r ( mqtt_connect_tls
        `emqx.homecloud.fi` 8883
        `qwerty` `qwerty` `qwerty` )

    ?? r {
        T reason → {
            ( nurl_print `CONNACK reason code = ` )
            ( nurl_print ( nurl_str_int reason ) )
            ( nurl_print `\n` )
            ? == reason 0 {
                ( nurl_print `CONNECTED — MQTT v5 session established.\n` )
                ^ 0
            } {
                ( nurl_print `broker refused the CONNECT (non-zero reason code).\n` )
                ^ 1
            }
        }
        F e → {
            ( nurl_eprint `connect failed: ` )
            ( nurl_eprint ( net_err_name e ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
