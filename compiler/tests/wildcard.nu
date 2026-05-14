// Wildcard _ test — catch-all arms in pattern matching

: | LogLevel {
    Debug
    Info
    Warn
    Error
    Fatal
}

: | Packet {
    Data i s
    Ack i
    Ping
    Pong
    Reset
    Close i
}

// 1. Wildcard lopussa — catch-all
@ level_emoji LogLevel lvl → s {
    ?? lvl {
        Error → `[!]`
        Fatal → `[X]`
        _ → `[.]`
    }
}

// 2. Wildcard keskellä — specifics + catch-all + specifics ei sallittu,
//    mutta wildcard EI tarvitse olla viimeinen JOS se on ainoa jäljellä
@ is_critical LogLevel lvl → b {
    ?? lvl {
        Fatal → T
        Error → T
        _ → F
    }
}

// 3. Wildcard payloadilla — bindatut arvot EI pura payloadia
//    _ on aina "kaikki muu", ei "mikä tahansa variantti jonka payload haluan"
@ describe_packet Packet p → s {
    ?? p {
        Data seq msg → msg
        Ack seq → ( nurl_str_int seq )
        Close code → ( nurl_str_int code )
        _ → `control`
    }
}

// 4. Vain wildcard — kaikki variantit samaan haaraan
@ packet_exists Packet p → b {
    ?? p {
        _ → T
    }
}

// 5. Wildcard + return value expression
@ severity LogLevel lvl → i {
    ?? lvl {
        Fatal → 5
        Error → 4
        Warn → 3
        _ → 1
    }
}

@ main → i {
    ( nurl_print `Wildcard pattern matching test...\n\n` )

    // Test 1: level_emoji
    ( nurl_print `level_emoji:\n` )
    ( nurl_print `  Debug: ` ) ( nurl_print ( level_emoji Debug ) ) ( nurl_print `\n` )
    ( nurl_print `  Info:  ` ) ( nurl_print ( level_emoji Info ) ) ( nurl_print `\n` )
    ( nurl_print `  Warn:  ` ) ( nurl_print ( level_emoji Warn ) ) ( nurl_print `\n` )
    ( nurl_print `  Error: ` ) ( nurl_print ( level_emoji Error ) ) ( nurl_print `\n` )
    ( nurl_print `  Fatal: ` ) ( nurl_print ( level_emoji Fatal ) ) ( nurl_print `\n` )

    // Test 2: is_critical
    ( nurl_print `\nis_critical:\n` )
    ( nurl_print `  Debug: ` ) ( nurl_print ? ( is_critical Debug ) `yes` `no` ) ( nurl_print `\n` )
    ( nurl_print `  Warn:  ` ) ( nurl_print ? ( is_critical Warn ) `yes` `no` ) ( nurl_print `\n` )
    ( nurl_print `  Error: ` ) ( nurl_print ? ( is_critical Error ) `yes` `no` ) ( nurl_print `\n` )
    ( nurl_print `  Fatal: ` ) ( nurl_print ? ( is_critical Fatal ) `yes` `no` ) ( nurl_print `\n` )

    // Test 3: describe_packet
    ( nurl_print `\ndescribe_packet:\n` )
    ( nurl_print `  Data:  ` ) ( nurl_print ( describe_packet @ Packet { Data 1 `hello` } ) ) ( nurl_print `\n` )
    ( nurl_print `  Ack:   ` ) ( nurl_print ( describe_packet @ Packet { Ack 42 } ) ) ( nurl_print `\n` )
    ( nurl_print `  Ping:  ` ) ( nurl_print ( describe_packet @ Packet { Ping } ) ) ( nurl_print `\n` )
    ( nurl_print `  Pong:  ` ) ( nurl_print ( describe_packet @ Packet { Pong } ) ) ( nurl_print `\n` )
    ( nurl_print `  Reset: ` ) ( nurl_print ( describe_packet @ Packet { Reset } ) ) ( nurl_print `\n` )
    ( nurl_print `  Close: ` ) ( nurl_print ( describe_packet @ Packet { Close 99 } ) ) ( nurl_print `\n` )

    // Test 4: packet_exists (wildcard only)
    ( nurl_print `\npacket_exists:\n` )
    ( nurl_print `  Ping:  ` ) ( nurl_print ? ( packet_exists @ Packet { Ping } ) `yes` `no` ) ( nurl_print `\n` )
    ( nurl_print `  Reset: ` ) ( nurl_print ? ( packet_exists @ Packet { Reset } ) `yes` `no` ) ( nurl_print `\n` )

    // Test 5: severity
    ( nurl_print `\nseverity:\n` )
    ( nurl_print `  Debug: ` ) ( nurl_print ( nurl_str_int ( severity Debug ) ) ) ( nurl_print `\n` )
    ( nurl_print `  Info:  ` ) ( nurl_print ( nurl_str_int ( severity Info ) ) ) ( nurl_print `\n` )
    ( nurl_print `  Warn:  ` ) ( nurl_print ( nurl_str_int ( severity Warn ) ) ) ( nurl_print `\n` )
    ( nurl_print `  Error: ` ) ( nurl_print ( nurl_str_int ( severity Error ) ) ) ( nurl_print `\n` )
    ( nurl_print `  Fatal: ` ) ( nurl_print ( nurl_str_int ( severity Fatal ) ) ) ( nurl_print `\n` )

    ^ 0
}
