// mqtt_codec.nu — offline regression for the MQTT 5.0 client codec.
//
// No network: every assertion runs against in-memory ( Vec u )
// buffers. Covers the Variable Byte Integer round-trip, the unsigned
// byte reader, MQTT UTF-8 string framing, the CONNECT packet layout,
// CONNACK reason extraction, MQTT 5 user-property parsing, the typed
// MqttErr names, and topic-filter wildcard matching (MQTT 5.0 §4.7).
//
// Pairs with example/mqtt_*.nu (live broker verification); this test
// is the CI-safe half — it never opens a socket.

$ `stdlib/ext/mqtt.nu`
$ `stdlib/core/vec.nu`

// Print a labelled byte buffer as `tag [len] b0 b1 ...`.
@ dump s tag ( Vec u ) v → v {
    ( nurl_print tag )
    ( nurl_print ` [` )
    ( nurl_print ( nurl_str_int ( vec_len [u] v ) ) )
    ( nurl_print `]` )
    : i n ( vec_len [u] v )
    : ~ i k 0
    ~ < k n {
        ( nurl_print ` ` )
        ( nurl_print ( nurl_str_int ( _mqtt_byte v k ) ) )
        = k + k 1
    }
    ( nurl_print `\n` )
}

// One varint round-trip: encode `val`, then report the encoded byte
// count, the decoded value + nbytes, and the framed reader's length.
@ chk_varint i val → v {
    : ( Vec u ) buf ( vec_new [u] )
    ( _mqtt_put_varint buf val )
    : MqttVarint mv ( _mqtt_decode_varint buf 0 )
    : i vl ( _mqtt_varint_len buf 0 )
    ( nurl_print `varint ` )
    ( nurl_print ( nurl_str_int val ) )
    ( nurl_print ` enc=` )
    ( nurl_print ( nurl_str_int ( vec_len [u] buf ) ) )
    ( nurl_print `B dec=` )
    ( nurl_print ( nurl_str_int . mv value ) )
    ( nurl_print ` nbytes=` )
    ( nurl_print ( nurl_str_int . mv nbytes ) )
    ( nurl_print ` len=` )
    ( nurl_print ( nurl_str_int vl ) )
    ( nurl_print ? & == . mv value val == . mv nbytes vl ` ok` ` FAIL` )
    ( nurl_print `\n` )
    ( vec_free [u] buf )
}

// One topic-match assertion vs. an expected verdict.
@ chk_match s filter s topic b expect → v {
    : b got ( mqtt_topic_matches filter topic )
    ( nurl_print `'` )
    ( nurl_print filter )
    ( nurl_print `' ~ '` )
    ( nurl_print topic )
    ( nurl_print `' = ` )
    ( nurl_print ? got `match` `nomatch` )
    ( nurl_print ? == got expect ` ok` ` FAIL` )
    ( nurl_print `\n` )
}

@ main → i {
    ( nurl_print `-- varint round-trip --\n` )
    ( chk_varint 0 )
    ( chk_varint 127 )
    ( chk_varint 128 )
    ( chk_varint 16383 )
    ( chk_varint 16384 )
    ( chk_varint 2097151 )
    ( chk_varint 2097152 )
    ( chk_varint 268435455 )

    ( nurl_print `-- unsigned byte reader --\n` )
    : ( Vec u ) bb ( vec_new [u] )
    ( vec_push [u] bb # u 0 )
    ( vec_push [u] bb # u 127 )
    ( vec_push [u] bb # u 128 )
    ( vec_push [u] bb # u 255 )
    ( nurl_print `byte0=` ) ( nurl_print ( nurl_str_int ( _mqtt_byte bb 0 ) ) ) ( nurl_print `\n` )
    ( nurl_print `byte2=` ) ( nurl_print ( nurl_str_int ( _mqtt_byte bb 2 ) ) ) ( nurl_print `\n` )
    ( nurl_print `byte3=` ) ( nurl_print ( nurl_str_int ( _mqtt_byte bb 3 ) ) ) ( nurl_print `\n` )
    ( nurl_print `byteOOB=` ) ( nurl_print ( nurl_str_int ( _mqtt_byte bb 9 ) ) ) ( nurl_print `\n` )
    ( vec_free [u] bb )

    ( nurl_print `-- MQTT string framing --\n` )
    : ( Vec u ) sb ( vec_new [u] )
    ( _mqtt_put_str sb `MQTT` )
    ( dump `str` sb )
    ( vec_free [u] sb )

    ( nurl_print `-- CONNECT layout --\n` )
    : MqttConfig cfg ( mqtt_config `cid7` `` `` )
    : ( Vec u ) cp ( vec_new [u] )
    ( _mqtt_encode_connect cp cfg )
    ( dump `connect` cp )
    ( vec_free [u] cp )

    ( nurl_print `-- CONNACK reason --\n` )
    : ( Vec u ) cok ( vec_new [u] )
    ( vec_push [u] cok # u 32 )  // CONNACK fixed-header type
    ( vec_push [u] cok # u 2 )  // remaining length
    ( vec_push [u] cok # u 0 )  // acknowledge flags
    ( vec_push [u] cok # u 0 )  // reason code 0 = Success
    ( nurl_print `connack_ok=` ) ( nurl_print ( nurl_str_int ( mqtt_connack_reason cok ) ) ) ( nurl_print `\n` )
    ( vec_free [u] cok )
    : ( Vec u ) cbad ( vec_new [u] )
    ( vec_push [u] cbad # u 32 )
    ( vec_push [u] cbad # u 2 )
    ( vec_push [u] cbad # u 0 )
    ( vec_push [u] cbad # u 134 )  // 0x86 Bad User Name or Password
    ( nurl_print `connack_bad=` ) ( nurl_print ( nurl_str_int ( mqtt_connack_reason cbad ) ) ) ( nurl_print `\n` )
    ( vec_free [u] cbad )
    : ( Vec u ) cshort ( vec_new [u] )
    ( vec_push [u] cshort # u 32 )
    ( nurl_print `connack_short=` ) ( nurl_print ( nurl_str_int ( mqtt_connack_reason cshort ) ) ) ( nurl_print `\n` )
    ( vec_free [u] cshort )

    ( nurl_print `-- user-property parse --\n` )
    : ( Vec u ) props ( vec_new [u] )
    ( vec_push [u] props # u 38 )  // 0x26 User Property
    ( _mqtt_put_str props `unit` )  // key
    ( _mqtt_put_str props `celsius` )  // value
    : ( Vec ( Pair String String ) ) parsed ( vec_new [( Pair String String )] )
    ( _mqtt_parse_props props 0 ( vec_len [u] props ) parsed )
    ( nurl_print `props=` ) ( nurl_print ( nurl_str_int ( vec_len [( Pair String String )] parsed ) ) ) ( nurl_print `\n` )
    ? > ( vec_len [( Pair String String )] parsed ) 0 {
        : *( Pair String String ) pd ( vec_data [( Pair String String )] parsed )
        : ( Pair String String ) p0 . pd 0
        ( nurl_print `  key=` ) ( nurl_print ( string_data . p0 first ) ) ( nurl_print `\n` )
        ( nurl_print `  val=` ) ( nurl_print ( string_data . p0 second ) ) ( nurl_print `\n` )
    } {}
    ( mqtt_props_free parsed )
    ( vec_free [u] props )

    ( nurl_print `-- MqttErr names --\n` )
    ( nurl_print ( mqtt_err_name # MqttErr MqttTransport ) ) ( nurl_print `\n` )
    ( nurl_print ( mqtt_err_name # MqttErr MqttTimeout ) ) ( nurl_print `\n` )
    ( nurl_print ( mqtt_err_name # MqttErr MqttClosed ) ) ( nurl_print `\n` )
    ( nurl_print ( mqtt_err_name # MqttErr MqttProtocol ) ) ( nurl_print `\n` )
    ( nurl_print ( mqtt_err_name # MqttErr MqttBadAuth ) ) ( nurl_print `\n` )
    ( nurl_print ( mqtt_err_name # MqttErr MqttSubFailed ) ) ( nurl_print `\n` )

    ( nurl_print `-- topic matching (MQTT 5.0 ~4.7) --\n` )
    // exact literal
    ( chk_match `sport/tennis/p1` `sport/tennis/p1` T )
    ( chk_match `sport/tennis` `sport/tennis/p1` F )
    // single-level wildcard `+`
    ( chk_match `sport/tennis/+` `sport/tennis/p1` T )
    ( chk_match `sport/tennis/+` `sport/tennis/p1/rank` F )
    ( chk_match `sport/+/p1` `sport/tennis/p1` T )
    ( chk_match `+` `a` T )
    ( chk_match `+` `a/b` F )
    ( chk_match `+/+` `a/b` T )
    ( chk_match `a/+` `a/` T )
    ( chk_match `a/+/c` `a/b` F )
    // multi-level wildcard `#`
    ( chk_match `sport/#` `sport/tennis/p1` T )
    ( chk_match `sport/#` `sport` T )
    ( chk_match `sport/#` `sport/` T )
    ( chk_match `#` `a/b/c` T )
    ( chk_match `a/b` `a/b/c` F )
    ( chk_match `a/b/c` `a/b` F )
    // §4.7.2 — a leading wildcard never matches a $-topic
    ( chk_match `#` `$SYS/broker` F )
    ( chk_match `+/monitor` `$SYS/monitor` F )
    ( chk_match `$SYS/#` `$SYS/broker/load` T )

    ^ 0
}
