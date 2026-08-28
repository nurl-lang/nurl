// Legit (must KEEP compiling): integer literals narrow into sized /
// unsigned fields on store; same-type struct/field writes are fine.
$ `stdlib/core/string.nu`

: P { u r u g i n }

@ main → i {
    : ~ P p @ P { 0 0 0 }
    = . p r 255
    = . p g 128
    = . p n 99
    ( nurl_println_int + + # i . p r # i . p g . p n )
    ^ 0
}
