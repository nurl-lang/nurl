// select_waiter_dropped_while_armed: `( chan_select_arm [i] ch w )` and then `w` dropped: the channel
// kept the waiter's raw address, SelWaiter's drop released its block, and
// the next chan_send fired the freed waiter. The lowering of `?? { }`
// always disarms first, but the functions are callable from any program.
// Closed: the waiter's block is counted (Shared), every channel it is
// armed on holds a share until the disarm, and a channel's drop lets its
// shares go (agora #167).
// v0.80.0: accepted; AddressSanitizer reported heap-use-after-free.
// map: §3.3d | B | runs-clean | h616 | `( chan_select_arm [i] ch w )`, `w` dropped, then `chan_send`: the channel fired the freed waiter by its raw address; the waiter is a Shared block each channel holds a share of while armed (agora #167).
$ `stdlib/std/channel.nu`

@ arm_and_drop ( Channel i ) ch → v {
    : SelWaiter w ( select_waiter_new )
    ( chan_select_arm [i] ch w )
}

@ main → i {
    : ( Channel i ) ch ( chan_new [i] )
    ( arm_and_drop ch )
    : b _s ( chan_send [i] ch 7 )
    ^ 0
}
