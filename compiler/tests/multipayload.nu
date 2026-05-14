: | Rect {
    Pos i i
    Size i i
    Empty
}

@ area Rect r → i {
    ?? r {
        Pos x y → *x y
        Size w h → *w h
        Empty → 0
    }
}

@ main → i {
    ( nurl_print `Multi-payload test...\n` )

    : Rect a @ Rect { Pos 3 7 }
    ( nurl_print `Pos 3 7: ` )
    ( nurl_print ( nurl_str_int ( area a ) ) )
    ( nurl_print `\n` )

    : Rect b @ Rect { Size 1920 1080 }
    ( nurl_print `Size 1920 1080: ` )
    ( nurl_print ( nurl_str_int ( area b ) ) )
    ( nurl_print `\n` )

    : Rect c @ Rect { Empty }
    ( nurl_print `Empty: ` )
    ( nurl_print ( nurl_str_int ( area c ) ) )
    ( nurl_print `\n` )

    ^ 0
}
