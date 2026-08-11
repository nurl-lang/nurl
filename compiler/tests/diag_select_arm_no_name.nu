// diag_select_arm_no_name.nu — a select arm whose '→' is followed
// straight by the body, with no name for the received value.
// Exposed by the same fingerprint fix as diag_select_arm_no_arrow.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) c ( chan_new [i] )
    ?? { [i] c → {} }
    ^ 0
}
