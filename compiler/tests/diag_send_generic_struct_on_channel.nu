// A Channel moves its values to whichever thread receives them, so its
// element type must be Send: a generic struct instance holding an `Rc` is
// not, by the fields the instance has (agora #675).
$ `stdlib/std/rc.nu`
$ `stdlib/std/channel.nu`

: Wrap [T] { ( Rc T ) held }

@ main → i {
    : ( Rc i ) mine ( rc_new [i] 5 )
    : ( Channel ( Wrap i ) ) ch ( chan_new [( Wrap i )] )
    : b sent ( chan_send [( Wrap i )] ch @ ( Wrap i ) { ( rc_clone [i] mine ) } )
    ^ 0
}
