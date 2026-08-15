// diag_send_chan_send.nu
// A channel is a thread boundary too: whatever `chan_send` accepts,
// some other thread or fiber receives. No closure is involved, so
// there is no build-time verdict to read — the argument's own type is
// the whole question.

$ `stdlib/std/thread.nu`
$ `stdlib/std/rc.nu`
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Rc i ) shared ( rc_new [i] 0 )
    : ( Channel ( Rc i ) ) ch ( chan_new [( Rc i )] )
    : b ok ( chan_send [( Rc i )] ch shared )
    ^ 0
}
