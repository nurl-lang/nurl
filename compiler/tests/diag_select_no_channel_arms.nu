// diag_select_no_channel_arms.nu — a select with only a default arm,
// which would spin without ever waiting.
$ `stdlib/std/channel.nu`

@ main → i {
    ?? { _ → {} }
    ^ 0
}
