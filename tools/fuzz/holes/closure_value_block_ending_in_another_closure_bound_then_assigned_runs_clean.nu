// map: §7.6 | A2 | runs-clean | - | AGORA-953 guard: `: g { … b }  = a g`, g a second name of another closure's env: a's own env is released, a borrows b's
$ `stdlib/core/string.nu`

@ main → i {
    : String tag ( string_from `tag string long enough for a heap buffer` )
    : ~ ( @ i i ) a \ i x → i { ^ + x ( string_len tag ) }
    : ( @ i i ) b \ i x → i { ^ + x 2 }
    : ( @ i i ) g { : i z ( a 1 ) b }
    = a g
    ( nurl_println_int ( a 1 ) )
    ^ 0
}
