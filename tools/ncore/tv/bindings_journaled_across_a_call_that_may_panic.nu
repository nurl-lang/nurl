$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: Bomb { String tag i boom }

% Drop Bomb { @ drop Bomb b → v { ( nurl_print `` ) } }

: Two { Bomb first Bomb mid Bomb last }

@ bomb i k → Bomb { ^ @ Bomb { ( string_from `a tag long enough for the heap` ) k } }

@ late i on → Bomb { ? == on 1 { ( panic `panic while building` ) } {} ^ ( bomb 9 ) }

@ flat → v { : Bomb b ( bomb 0 ) : Two t @ Two { b ( bomb 1 ) ( late 1 ) } }

@ main → i {
    : !v PanicInfo a ( recover \ → v { ( flat ) } )
    ^ 0
}
