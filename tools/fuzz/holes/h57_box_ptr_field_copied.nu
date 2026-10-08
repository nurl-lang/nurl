// H57: a Box literal built from another Box's ptr field: two owners.
$ `stdlib/core/box.nu`

@ main → i {
    : ( Box i ) a ( box_new [i] 5 )
    : ( Box i ) b @ ( Box i ) { . a ptr }
    ( nurl_println_int ( box_get [i] b ) )
    ^ 0
}
