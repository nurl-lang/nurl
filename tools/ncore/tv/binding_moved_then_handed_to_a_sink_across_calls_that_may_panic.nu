$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `a tag long enough for the heap` ) k } }

@ late i on → Bomb { ? == on 1 { ( panic `panic while building` ) } {} ^ ( bomb 9 ) }

@ eat sink Bomb b → i { ^ 0 }

@ flat i n → v {
    : ~ Bomb b ( bomb 0 )
    : Bomb w b
    : Bomb x ( late n )
    : i z ( eat w )
    : Bomb y ( late 0 )
}

@ main → i {
    : !v PanicInfo a ( recover \ → v { ( flat 1 ) } )
    ^ 0
}
