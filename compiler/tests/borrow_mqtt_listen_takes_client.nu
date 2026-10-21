// borrow_mqtt_listen_takes_client.nu
// mqtt_listen hands the client to a reader thread that changes its buffers
// and packet-id state with no lock. Its doc used to ask the caller not to
// call other mqtt_* functions on the client while the thread ran; nothing
// made it, and a publish on the caller's thread raced the reader. The
// client is a `sink` parameter now: after mqtt_listen it is gone.

$ `stdlib/ext/mqtt.nu`

@ main → i {
    ?? ( mqtt_connect `127.0.0.1` 1 `c` `` `` ) {
        T cl → {
            ?? ( mqtt_listen cl ) { T l → { ( mqtt_listener_stop l ) } F _ → {} }
            : !v MqttErr r ( mqtt_ping cl )
        }
        F _ → { ( puts `no broker` ) }
    }
    ^ 0
}
