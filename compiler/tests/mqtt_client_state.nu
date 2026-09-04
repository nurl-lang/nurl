// mqtt_client_state.nu — the MqttClient state that must survive a
// method call. No network: a client is built over a dummy TcpConn and
// only the pure state helpers are exercised.
//
// Both fields regressed the same way and for the same reason. They
// were plain `i` fields on MqttClient, and every method takes the
// client BY VALUE, so `= . cl next_pid nxt` and `= . cl ping_deadline
// …` wrote to the method's own copy:
//
//   * __mqtt_next_pid returned 1 forever, so every QoS 1/2 PUBLISH,
//     SUBSCRIBE and UNSUBSCRIBE went on the wire with packet id 1 —
//     the one thing MQTT 5 §2.2.1 requires to differ between packets
//     in flight.
//   * the keep-alive deadline never moved, so once it first expired
//     every mqtt_keepalive_tick sent another PINGREQ: an idle loop
//     turned into a ping flood at loop speed.
//
// They now live in `ctl`, a ( Vec i ) whose control block is shared
// across copies (as `rxbuf` and `qos2_rx` always were). This test
// pins the sharing: it calls the helpers exactly as a method would —
// through a by-value client — and checks the caller sees the writes.

$ `stdlib/ext/mqtt.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/net.nu`

// A client over a conn that is never read or written.
@ dummy_client i keepalive_ms → MqttClient {
    : TcpConn conn @ TcpConn { `` 0 0 }
    ^ @ MqttClient { conn ( vec_new [u] ) ( __mqtt_ctl_new 0 ) keepalive_ms
        ( vec_new [i] ) F }
}

@ free_client MqttClient cl → v {
    ( vec_free [u] . cl rxbuf )
    ( vec_free [i] . cl qos2_rx )
    ( vec_free [i] . cl ctl )
}

// Allocate `n` ids the way a publish path does — one call per packet.
@ take_ids MqttClient cl i n → v {
    : ~ i k 0
    ~ < k n {
        ( nurl_print ( nurl_str_int ( __mqtt_next_pid cl ) ) )
        ( nurl_print ` ` )
        = k + k 1
    }
    ( nurl_print `\n` )
}

@ main → i {
    ( nurl_print `--- packet ids advance ---\n` )
    : MqttClient cl ( dummy_client 60000 )
    ( take_ids cl 5 )
    // …and keep advancing across a second call, i.e. the counter is in
    // the client, not in take_ids' copy of it.
    ( take_ids cl 3 )

    ( nurl_print `--- id wraps at 65535, never to 0 ---\n` )
    ( vec_set [i] . cl ctl MQTT_CTL_NEXT_PID 65534 )
    ( take_ids cl 4 )

    ( nurl_print `--- keep-alive deadline moves ---\n` )
    : i d0 ( __mqtt_deadline cl )
    ( __mqtt_deadline_bump cl )
    : i d1 ( __mqtt_deadline cl )
    ( nurl_print `bumped=` )
    ( nurl_print ? > d1 d0 `T` `F` )
    ( nurl_print `\n` )
    // A zero keep-alive still bumps to "now", never stays at 0 — the
    // tick path reads this before deciding to ping.
    ( nurl_print `nonzero=` )
    ( nurl_print ? > d1 0 `T` `F` )
    ( nurl_print `\n` )

    ( free_client cl )
    ^ 0
}
