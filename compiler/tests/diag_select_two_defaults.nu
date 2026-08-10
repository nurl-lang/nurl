// diag_select_two_defaults.nu — two default arms in one select.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) c ( chan_new [i] )
    ?? { [i] c → v {} _ → {} _ → {} }
    ^ 0
}
