// example/mqtt_test.nu — MQTT v5 client connect smoke test.
//
// Connects to an MQTT 5.0 broker over TLS and runs the CONNECT
// handshake (clientId / username / password).
//
//   broker   : emqx.homecloud.fi:8883  (MQTT over TLS)
//   clientId : qwerty   username : qwerty   password : qwerty
//
// Build & run:
//   ./nurl.sh example/mqtt_test.nu example/mqtt_test
//   ./example/mqtt_test

$ `stdlib/ext/mqtt.nu`

@ main → i {
    ( nurl_print `MQTT v5 → emqx.homecloud.fi:8883 (TLS), clientId=qwerty\n` )

    : !MqttClient MqttErr r ( mqtt_connect
        `emqx.homecloud.fi` 8883
        `qwerty` `qwerty` `qwerty` )

    ?? r {
        T cl → {
            ( nurl_print `CONNECTED — MQTT v5 session established.\n` )
            ( mqtt_disconnect cl )
            ^ 0
        }
        F e → {
            ( nurl_eprint `connect failed: ` )
            ( nurl_eprint ( mqtt_err_name e ) )
            ( nurl_eprint `\n` )
            ^ 1
        }
    }
}
