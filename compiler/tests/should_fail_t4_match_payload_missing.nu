// t4_match_payload_missing.nu
// JNum puuttuu, ei _ → compile error
// Odotettu: compile error "non-exhaustive match on Json, unhandled: JNum"

: | Json { JNull JBool b JNum i }

@ json_str Json j → s {
    ^ ?? j {
        JNull → `null`
        JBool v → ?v `true` `false`
    }
}

@ main → i {
    ( nurl_print ( json_str @ Json { JNull } ) )
    ^ 0
}
