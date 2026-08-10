// diag_select_arm_body_unbraced.nu — a select arm body written bare.
// Every select arm body is braced, even a one-expression one.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) c ( chan_new [i] )
    ?? { [i] c → v ^ 0 }
    ^ 0
}
