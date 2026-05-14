: | Event {
    Click i
    KeyPress s
    Close
}

@ describe_event Event e → s {
    ?? e {
        Click x → ( nurl_str_int x )
        KeyPress k → k
        Close → `closed`
    }
}

@ main → i {
    ( nurl_print `Payload value test...\n` )

    : Event a @ Event { Click 42 }
    ( nurl_print `Click: ` )
    ( nurl_print ( describe_event a ) )
    ( nurl_print `\n` )

    : Event b @ Event { KeyPress `enter` }
    ( nurl_print `KeyPress: ` )
    ( nurl_print ( describe_event b ) )
    ( nurl_print `\n` )

    : Event c @ Event { Close }
    ( nurl_print `Close: ` )
    ( nurl_print ( describe_event c ) )
    ( nurl_print `\n` )

    ^ 0
}
