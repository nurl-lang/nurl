// t3_match_wildcard.nu
// Vain Red eksplisiittisesti, _ kattaa Green ja Blue

: | Color { Red Green Blue }

@ color_name Color c → s {
    ^ ?? c {
        Red → `red`
        _ → `other`
    }
}

@ main → i {
    ( nurl_print `--- 4.1 Test 3: Wildcard ---\n` )

    ( nurl_print `Red:   ` )
    ( nurl_print ( color_name @ Color { Red } ) )
    ( nurl_print `\n` )

    ( nurl_print `Green: ` )
    ( nurl_print ( color_name @ Color { Green } ) )
    ( nurl_print `\n` )

    ( nurl_print `Blue:  ` )
    ( nurl_print ( color_name @ Color { Blue } ) )
    ( nurl_print `\n` )

    ( nurl_print `PASS\n` )
    ^ 0
}
