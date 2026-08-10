// diag_select_arm_unterminated.nu — a select arm whose '[' never closes.
// The scan runs to EOF, so the diagnostic has no useful token to point
// at and must carry the whole arm shape in the text instead.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) c ( chan_new [i] )
    ?? { [i c → v {} }
    ^ 0
}
