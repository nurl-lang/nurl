// diag_select_default_body_unbraced.nu — the default arm's body written
// bare. Every select arm body is braced.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) c ( chan_new [i] )
    ?? { [i] c → v {} _ → ^ 0 }
    ^ 0
}
